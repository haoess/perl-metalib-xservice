use warnings;
use strict;

use Test::More;
use MetaLib::XService;

if(
    !defined $ENV{TEST_METALIB_XSERVICE_URL} &&
    !defined $ENV{TEST_METALIB_XSERVICE_USER} &&
    !defined $ENV{TEST_METALIB_XSERVICE_PASSWORD} 
) {
    plan skip_all => 'no testing environment set';
}
else {
    plan tests => 11;
}

my $m = MetaLib::XService->new({ host => $ENV{TEST_METALIB_XSERVICE_URL} });
my $login = $m->login({
    user     => $ENV{TEST_METALIB_XSERVICE_USER},
    password => $ENV{TEST_METALIB_XSERVICE_PASSWORD},
});

my $find = $m->find;
is( $find, undef, 'no args' );
is( ref $m->error, 'MetaLib::XService::Error', 'error set' );
is( $m->error->code, 2038, 'error code' );
is( $m->error->msg, '2038 Missing line', 'error message' );
is( $m->error->type, 'local', 'local error' );

$find = $m->find({
    search => 'WAU=(thomas macho)',
});
is( $find, undef, 'no source' );
is( ref $m->error, 'MetaLib::XService::Error', 'error set' );
is( $m->error->code, 2039, 'error code' );
is( $m->error->msg, '2039 Missing line', 'error message' );
is( $m->error->type, 'local', 'local error' );

$find = $m->find({
    search => 'WAU=(thomas macho)',
    resource => 'KOB06529',
});
is( defined $find, 1, 'search request' );
