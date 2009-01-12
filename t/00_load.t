#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'MetaLib::XService' );
}

diag( "Testing MetaLib::XService $MetaLib::XService::VERSION, Perl $], $^X" );
