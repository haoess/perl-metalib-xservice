use warnings;
use strict;

use Test::More tests => 13;
use MetaLib::XService;

my $m = MetaLib::XService->new({ host => 'http://example.com/X' });
my $login = $m->login({
    user     => 'example',
    password => 'example',
});
is( $login, undef, 'no successful login' );
is( defined $m->session, '', 'no session set' );
is( ref $m->error, 'MetaLib::XService::Error', 'error set' );
is( $m->error->type, 'http', 'HTTP error' );
is( $m->error->code, 404, 'error code: 404' );
is( $m->error->msg, 'Not Found', 'error message: not found' );

###

SKIP: {
    skip 'no testing environment set', 7 if
        !defined $ENV{TEST_METALIB_XSERVICE_URL} &&
        !defined $ENV{TEST_METALIB_XSERVICE_USER} &&
        !defined $ENV{TEST_METALIB_XSERVICE_PASSWORD};

    $m = MetaLib::XService->new({ host => $ENV{TEST_METALIB_XSERVICE_URL} });
    is( ref $m, 'MetaLib::XService' );

    $login = $m->login({
        user     => $ENV{TEST_METALIB_XSERVICE_USER},
        password => $ENV{TEST_METALIB_XSERVICE_PASSWORD},
    });
    is( $login, 1, 'login successful' );
    is( $m->error, undef, 'no error set' );
    is( defined $m->session, 1, 'session set' );

    $m = MetaLib::XService->new({ host => $ENV{TEST_METALIB_XSERVICE_URL} });
    $login = $m->login({
        user => 'does_not_exist',
        password => 'does_not_exist',
    });
    is( $login, undef, 'no successful login' );
    is( defined $m->session, '', 'no session set' );
    is( defined $m->error, '', 'no error set');
}
