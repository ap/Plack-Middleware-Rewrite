use Test::More tests => 1;

BEGIN {
use_ok( 'Plack::Middleware::Rewrite' )
or BAIL_OUT( 'testing pointless if the module won\'t even load' );
}
