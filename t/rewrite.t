use strict;
no warnings;
use Plack::Test;
use Plack::Builder;
use Test::More;
use HTTP::Request::Common;

my $app = sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ $_[0]{'PATH_INFO'} ] ] };

my $xhtml = 'application/xhtml+xml';

$app = builder {
	enable 'Rewrite', rules => sub {
		return 301
			if s{^/foo/?$}{/bar/};

		return 201
			if $_ eq '/favicon.ico';

		return [ 404, [ 'Content-Type' => 'text/plain' ], [ 'Goodbye Web' ] ]
			if $_ eq '/die';

		return sub { $_->set( 'Content-Type', $xhtml ) }
			if $_[0]{'HTTP_ACCEPT'} =~ m{application/xhtml\+xml(?!\s*;\s*q=0)};

		s{^/baz$}{/quux};
	};
	$app;
};

test_psgi app => $app, client => sub {
	my $cb = shift;

	my ( $req, $res );

	$req = GET 'http://localhost/';
	$res = $cb->( $req );
	is $res->code, 200, 'Pass-through leaves status alone';
	is $res->content, '/', '... and the body';
	is $res->header( 'Content-Type' ), 'text/plain', '... as well as existing headers';
	ok !$res->header( 'Location' ), '... without adding any';

	$req = GET 'http://localhost/favicon.ico';
	$res = $cb->( $req );
	is $res->code, 201, 'Intercepts change the status';
	ok !$res->content, '... and prevent execution of the wrapped app';

	$req = GET 'http://localhost/baz';
	$res = $cb->( $req );
	is $res->content, '/quux', 'Internal rewrites affect the wrapped app';
	ok !$res->header( 'Location' ), '... without redirecting';

	$req = GET 'http://localhost/foo';
	$res = $cb->( $req );
	is $res->code, 301, 'Redirects change the status';
	is $res->header( 'Location' ), 'http://localhost/bar/', '... and produce the right Location';
	ok !$res->content, '... and prevent execution of the wrapped app';

	$req = GET 'http://localhost/die';
	$res = $cb->( $req );
	is $res->code, 404, 'Responses can be wholly fabricated';
	is $res->header( 'Content-Type' ), 'text/plain', '... with headers';
	is $res->content, 'Goodbye Web', '... body, and all.';

	$req = GET 'http://localhost/', Accept => $xhtml;
	$res = $cb->( $req );
	is $res->code, 200, 'Post-modification leaves the status alone';
	is $res->content, '/', '... and the body';
	ok !$res->header( 'Location' ), '... and inserts no Location header';
	is $res->header( 'Content-Type' ), $xhtml, '... but affects the desired headers';

	$req = GET 'http://localhost/', Accept => "$xhtml;q=0";
	$res = $cb->( $req );
	is $res->header( 'Content-Type' ), 'text/plain', '... and triggers only as requested';
};

done_testing;
