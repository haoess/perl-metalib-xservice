package MetaLib::XService;

use warnings;
use strict;

$MetaLib::XService::VERSION = '0.01';

use MetaLib::XService::Error;

use LWP::UserAgent;
use XML::LibXML;
use XML::Simple;

=head1 NAME

MetaLib::XService - Access MetaLib's X-Service.

=head1 SYNOPSIS

    # instantiate new object and set the host of the MetaLib X-Service
    my $m = MetaLib::XService->new({ host => 'http://host:8000/X' });

    my $login = $m->login({
        user     => 'username',
        password => 'secret',
    });
    if ( !$login ) {
        if ( $m->error ) {
            die sprintf "Could not login: %s (%d)", $m->error->msg, $m->error->code;
        }
        else {
            die "wrong credentials";
        }
    }

    # let's search for some famouse c. s. authors in two resources
    my $search = 'WAU=Knuth OR WAU=Tanenbaum';
    $m->find({
       resource => ['res1', 'res2'],
       search   => $search,
       wait     => 'N',
    });
    if ( $m->error ) {
        die sprintf "Could not find '%s': %s (%d)", $search, $m->error->msg, $m->error->code;
    }

    # wait until searching in both resources has finished
    while(1) {
        my $status = $m->find_status();
        if ( $status->{res1} eq 'DONE' && $status->{res2} eq 'DONE' ) {
            print "Search finished.\n";
            my $hits = 0;
            $hits += $_->{hits} for values %$s;
            printf "Total hits: %d\n", $hits;
            last;
        }
        print "Still searching ...\n";
        sleep 2;
    }

    # merge and sort results
    my $hits = $m->merge_sort({
        action         => 'merge',
        sort_primary   => 'rank',
        sort_secondary => 'title',
    });

    printf "%d hits after merging\n", $hits;

    # fetch the results
    my $results = $m->present({
        full_text => 'Y',
        format    => 'marc',
        view      => 'brief',
    });

    # process only results that provide full text
    foreach my $result ( @$results ) {
        # at this stage, you can process the xml like this:
        my $rec = MARC::Record->new_from_xml( $result );
        print $rec->title;
        ...
    }

=head1 VERSION

    0.01

=head1 DESCRIPTION

to be written ...

=head1 METHODS

=head2 new

=cut

sub new {
    my ($class, $args) = @_;
    my $self = bless {} => $class;
    $self->{host} = $args->{host};
    $self->{ua}   = LWP::UserAgent->new;
    return $self;
}

=head2 login

    my $login = $m->login({
        user     => 'username',
        password => 'secret',
    });
    if ( !$login ) {
        if ( $m->error ) {
            print "an error occured";
        }
        else {
            print "wrong credentials";
        }
    }

Processes the login and gets a new session id. You should provide
the credentials as a hash reference like

    my $credentials = {
        user     => 'username',
        password => 'secret',
    };
    $m->login($credentials);

Returns true if the login was successful. If not (and no HTTP or
request error occured) it returns false.

=cut

sub login {
    my ($self, $args) = @_;

    undef $self->{error};

    my $tpl = <<EOT;
<?xml version="1.0" encoding="UTF-8"?>
<x_server_request>
  <login_request>
    <user_name>%s</user_name>
    <user_password>%s</user_password>
  </login_request>
</x_server_request>
EOT

    my $body = sprintf $tpl,
                   _enc($args->{user}),
                   _enc($args->{password});

    my $res = $self->ua->post($self->host, { xml => $body });
    if ( !$res->is_success ) {
        $self->{error} = MetaLib::XService::Error->new({
            code    => $res->code,
            content => $res->content,
            msg     => $res->message,
            type    => 'http',
        });
        return;
    }
    my $xml = XMLin($res->content);

    if ( my $error = $xml->{login_response}{local_error} ) {
        $self->{error} = MetaLib::XService::Error->new({
            code    => $error->{error_code},
            content => $res->content,
            msg     => $error->{error_text},
            type    => 'local',
        });
        return;
    }

    my $auth = $xml->{login_response}{auth};
    if ( $auth ne 'Y' ) {
        return;
    }
    $self->{session} = $xml->{login_response}{session_id}{content};
    return 1;
}

=head2 find

    # search in 'resource1' for everything about 'computers'
    my $find = $m->find(
        resource => 'resource1',
        search   => 'WRD=computers',
    );

    # search in 'res1' and 'res2' for publications from 'Knuth'
    # or 'Tanenbaum', don't wait
    my $find = $m->find({
        resource => ['res1', 'res2'],
        search   => 'WAU=Knuth OR WAU=Tanenbaum',
        wait     => 'N',
    });

    if ( !$find ) {
        die "error: " . $m->error->{msg};
    }

C<$args> should provide:

=over 4

=item * resource

    resource => 'res',
    # or
    resource => ['res1', 'res2'],

A list of resources to search in. If you want to search only a single
resource, you can also provide a string.

=item * search

    search => $search,

A search string.

=item * wait

    wait => 'N',

Possible values: C<N> or C<Y> (default).

C<N> indicates that the search is running in background. You'll have to call C<search_info>
(repeatedly) to gather information if the search has finished.

C<Y> waits until the search has finished (default).

=back

Returns 1 if the search request was successful. If the request to all resources
failed, it returns nothing (and sets C<< $m->error >>). If some resources could
be successfully searched and some not, it returns 1 and sets C<< $m->error >>.

=cut

sub find {
    my ($self, $args) = @_;

    undef $self->{error};

    my $resources = $args->{resource};
    $resources = [$resources] unless ref $resources eq 'ARRAY';

    my $tpl = <<EOT;
<?xml version = "1.0" encoding = "UTF-8"?>
<x_server_request>
  <find_request>
    <wait_flag>%s</wait_flag>
    <find_request_command>%s</find_request_command>
    <session_id>%s</session_id>
    %s
  </find_request>
</x_server_request>
EOT

    my $base_tpl = <<EOT;
    <find_base>
      <find_base_001>%s</find_base_001>
    </find_base>
EOT

    my $bases = q{};
    for my $resource (@$resources) {
        $bases .= sprintf $base_tpl, _enc($resource);
    }

    my $body = sprintf $tpl,
                   _enc($args->{'wait'}),
                   _enc($args->{search}),
                   _enc($self->session),
                   $bases;

    my $res = $self->ua->post($self->host, { xml => $body });
    if ( !$res->is_success ) {
        $self->{error} = MetaLib::XService::Error->new({
            code    => $res->code,
            content => $res->content,
            msg     => $res->message,
            type    => 'http',
        });
        return;
    }
    my $xml = XMLin($res->content);

    if ( my $error = $xml->{find_response}{local_error} ) {
        $error = [$error] if ref $error ne 'ARRAY';
        foreach my $e (@$error) {
            push @{ $self->{error} }, MetaLib::XService::Error->new({
                code    => $e->{error_code},
                content => $res->content,
                msg     => $e->{error_text},
                type    => 'local',
            });
        }
    }

    my $group = $xml->{find_response}{group_number};
    if ( !$group ) {
        return;
    }

    $self->{group} = $group;
    return 1;
}

=head2 find_status

    my $status = $m->find_status;

Returns a hash ref like

    {
        res1 => {
            status => 'FIND'
            hits   => 0,
        },
        res2 => {
            status => 'DONE',
            hits   => 42,
        },
    }

This is only useful if you searched with the C<wait> flag
set (see C<find>).

STATUS can be one of these VALUES:

=over 4

=item * FORK

Before search.

=item * FIND

Search.

=item * FETCH

Start the first fetch process.

=item * DONE1

10 records fetched.

=item * DONE2

20 records fetched.

=item * DONE3

30 records fetched.

=item * DONE

All records fetched.

=item * STOP

Time out occured.

=item * ERROR

An error occured.

=item * ALLOW

Not allowed to search on resource,

=back

=cut

sub find_status {
    my $self = shift;

    undef $self->{error};

    my $tpl = <<EOT;
<?xml version="1.0" encoding="UTF-8"?>
<x_server_request>
  <find_group_info_request>
    <session_id>%s</session_id>
    <group_number>%s</group_number>
  </find_group_info_request>
</x_server_request>
EOT

    my $body = sprintf $tpl,
                   _enc($self->session),
                   _enc($self->{group});

    my $res = $self->ua->post($self->host, { xml => $body });
    if ( !$res->is_success ) {
        $self->{error} = MetaLib::XService::Error->new({
            code    => $res->code,
            content => $res->content,
            msg     => $res->message,
            type    => 'http',
        });
        return;
    }
    my $xml = XMLin($res->content);

    if ( my $error = $xml->{global_error} ) {
        $self->{error} = MetaLib::XService::Error->new({
                code    => $error->{error_code},
                content => $res->content,
                msg     => $error->{error_text},
                type    => 'local',
        });
        return;
    }

    my $info = $xml->{find_group_info_response}{base_info};
    $info = [$info] if ref $info ne 'ARRAY';

    my $status = {};

    foreach my $base (@$info) {
        next unless $base->{base_001};
        $status->{ $base->{base_001} } = {
            status => $base->{find_status},
            hits   => $base->{no_of_documents},
        }
    }

    return $status;
}

=head2 merge_sort

    my $hits = $m->merge_sort({
        action         => 'merge',
        sort_primary   => 'rank',
        sort_secondary => 'title',
    });

C<action> can be one of the following:

=over 4

=item * merge

Merge records retrieved up to this point in search process.

=item * merge_more

Retrieve additional records and remerge with existing merged set.

=item * merge_more_set

Retrieve additional records, clear the previous merged set and merge only
the new records.

=item * remerge

Delete last merged set and remerge records retrieved up to this point in
search process (applies to asyncronic search request or after using the
C<merge_more_set> action).

=item * sort_only

Sort existing merged set.

=back

If C<sort_primary> is not specified, default is by database.

If C<sort_secondary> is not specified, sort only by C<sort_primary>.

C<sort_primary> and C<sort_secondary> can be one of the following:

=over 4

=item * rank

=item * title

=item * author

=item * year

=item * database

=back

Returns the number of hits after merging/sorting.

B<Please note:> After the first merging you'll get less hits than
before merging. You'll get more results if you call C<merge_sort> again
with

    $m->merge_sort({
        action => 'merge_more'
    });

set.

=cut

sub merge_sort {
    my ($self, $args) = @_;

    undef $self->{error};

    my $tpl = <<EOT;
<?xml version="1.0" encoding="UTF-8"?>
<x_server_request>
  <merge_sort_request>
    <group_number>%s</group_number>
    <action>%s</action>
    <primary_sort_key>%s</primary_sort_key>
    <secondary_sort_key>%s</secondary_sort_key>
    <session_id>%s</session_id>
  </merge_sort_request>
</x_server_request>
EOT

    my $body = sprintf $tpl,
                 _enc($self->{group}),
                 _enc($args->{action}),
                 _enc($args->{primary_sort}),
                 _enc($args->{secondary_sort}),
                 _enc($self->session);

    my $res = $self->ua->post($self->host, { xml => $body });
    if ( !$res->is_success ) {
        $self->{error} = MetaLib::XService::Error->new({
            code    => $res->code,
            content => $res->content,
            msg     => $res->message,
            type    => 'http',
        });
        return;
    }
    my $xml = XMLin($res->content);

    if ( my $error = $xml->{merge_sort_response}{local_error} ) {
        $self->{error} = MetaLib::XService::Error->new({
            code    => $error->{error_code},
            content => $res->content,
            msg     => $error->{error_text},
            type    => 'local',
        });
        return;
    }

    $self->{set} = $xml->{merge_sort_response}{new_set_number};

    return $xml->{merge_sort_response}{no_of_documents};
}

=head2 present

    my $results = $m->present({
        format    => 'marc',
        full_text => 'Y',
        view      => 'brief',
        entries   => [1..20],
    });

Fetches the results as a array ref with a MARCXML record
for each hit.

=cut

sub present {
    my ($self, $args) = @_;

    $args->{entries} = join ',' => @{$args->{entries}};

    my $tpl = <<EOT;
<?xml version="1.0" encoding="UTF-8"?>
<x_server_request>
  <present_request>
    <session_id>%s</session_id>
    <present_command>
      <set_number>%06d</set_number>
      <set_entry>%s</set_entry>
      <format>%s</format>
      <full_txt>%s</full_txt>
      <view>%s</view>
    </present_command>
  </present_request>
</x_server_request>
EOT

    my $body = sprintf $tpl,
                   _enc($self->session),
                   _enc($self->{set}),
                   _enc($args->{entries}),
                   _enc($args->{format}),
                   _enc($args->{full_text}),
                   _enc($args->{view});

    my $res = $self->ua->post($self->host, { xml => $body });
    if ( !$res->is_success ) {
        $self->{error} = MetaLib::XService::Error->new({
            code    => $res->code,
            content => $res->content,
            msg     => $res->message,
            type    => 'http',
        });
        return;
    }

    my $parser = XML::LibXML->new;

    my $content = $res->content;

    # remove some metalib crap
    $content =~ s{<datafield tag="YR ".*?</datafield>}{}gs;

    my $document = $parser->parse_string($content);
    my @records = map { $_->toString } $document->getElementsByTagName('record');
    return \@records;
}

=head2 ua

    my $ua = $m->ua;

Returns the L<LWP::UserAgent>.

=cut

sub ua { return shift->{ua} }

=head2 host

    my $host = $m->host;

Returns host (provided to the C<new> constructor).

=cut

sub host { return shift->{host} }

=head2 session

    my $session = $m->session;

Returns the session string.

=cut

sub session { return shift->{session} }

=head2 error

    my $error = $m->error;
    # or
    my @errors = $m->error;

In scalar context: returns a L<MetaLib::XService::Error> object (the
first error that occured).

In list context: returns a list of L<MetaLib::XService::Error> objects.

=cut

sub error {
    my $self = shift;
    return unless $self->{error};
    if ( ref $self->{error} ne 'ARRAY' ) {
        return $self->{error};
    }
    if ( wantarray ) {
        return @{ $self->{error} }
    }
    else {
        return $self->{error}[0];
    }
}

sub _enc {
    my $str = shift || '';
    for ($str) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
    }
    return $str
}

=head1 TODO

More documentation, more features.

=head1 BUGS

Please report bugs relevant to C<MetaLib::XService> to E<lt>frank.wiegand[at]gmail.comE<gt>.

=head1 SEE ALSO

L<LWP::UserAgent>, L<XML::Simple>.

=head1 AUTHOR

Frank Wiegand, E<lt>frank.wiegand[at]gmail.comE<gt>

=head1 LICENSE AND COPYRIGHT

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Copyright 2008, 2009 by Frank Wiegand

=cut

1;
