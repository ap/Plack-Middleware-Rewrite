use strict;
no warnings;
use Plack::Test;
use Plack::Builder;
use Test::More;
use HTTP::Request::Common;

my $did_run;
my $app = sub { $did_run = 1; [ 200, [ 'Content-Type' => 'text/plain' ], [ $_[0]{'PATH_INFO'} ] ] };

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

		return [ 302, [ Location => 'http://localhost/correct' ], [] ]
			if m{^/psgi-redirect};

		return [ 302, [ qw( Content-Length 0 ) ], [] ]
			if s{^/nobody/?$}{/somebody/};

		return 303
			if s{^/fate/?$}{/tempted&badly/};

		s{^/baz$}{/quux};
	};
	$app;
};

test_psgi app => $app, client => sub {
	my $cb = shift;

	my ( $req, $res );

	my $run = sub { $did_run = 0; goto &$cb };

	$req = GET 'http://localhost/';
	$res = $run->( $req );
	is $did_run, 1, 'Pass-through works';
	is $res->code, 200, '... and leaves status alone';
	is $res->content, '/', '... as well as the the body';
	is $res->header( 'Content-Type' ), 'text/plain', '... and existing headers';
	ok !$res->header( 'Location' ), '... without adding any';

	$req = GET 'http://localhost/favicon.ico';
	$res = $run->( $req );
	is $did_run, 0, 'Intercepts prevent execution of the wrapped app';

	$req = GET 'http://localhost/baz';
	$res = $run->( $req );
	is $res->content, '/quux', 'Internal rewrites affect the wrapped app';
	ok !$res->header( 'Location' ), '... without redirecting';

	{ my $t = 'http://localhost/bar/';
	$req = GET 'http://localhost/foo';
	$res = $run->( $req );
	is $did_run, 0, 'Redirects prevent execution of the wrapped app';
	is $res->code, 301, '... and change the status';
	is $res->header( 'Location' ), $t, '... and produce the right Location';
	is $res->header( 'Content-Type' ), 'text/html', '... with a proper Content-Type';
	like $res->content, qr!<a href="\Q$t\E">!, '... for the stub body';
	}

	$req = GET 'http://localhost/fate';
	$res = $run->( $req );
	like $res->content, qr!<a href="http://localhost/tempted&amp;badly/">!, '... which is XSS-safe';

	$req = GET 'http://localhost/favicon.ico';
	$res = $run->( $req );
	is $res->code, 201, 'Body-less statuses are recognized';
	ok !$res->content, '... and no body generated for them';

	$req = GET 'http://localhost/foo?q=baz';
	$res = $run->( $req );
	is $res->header( 'Location' ), 'http://localhost/bar/?q=baz', 'Query strings are untouched';

	$req = GET 'http://localhost/die';
	$res = $run->( $req );
	is $res->code, 404, 'Responses can be wholly fabricated';
	is $res->header( 'Content-Type' ), 'text/plain', '... with headers';
	is $res->content, 'Goodbye Web', '... body, and all.';

	$req = GET 'http://localhost/psgi-redirect';
	$res = $run->( $req );
	is $res->code, 302, 'Fabricated responses can be redirects';
	is $res->header( 'Location' ), 'http://localhost/correct', '... with proper destination';

	$req = GET 'http://localhost/nobody';
	$res = $run->( $req );
	ok !$res->content, '... and can eschew the auto-generated body';

	$req = GET 'http://localhost/', Accept => $xhtml;
	$res = $run->( $req );
	is $res->code, 200, 'Post-modification leaves the status alone';
	is $res->content, '/', '... and the body';
	ok !$res->header( 'Location' ), '... and inserts no Location header';
	is $res->header( 'Content-Type' ), $xhtml, '... but affects the desired headers';

	$req = GET 'http://localhost/', Accept => "$xhtml;q=0";
	$res = $run->( $req );
	is $res->header( 'Content-Type' ), 'text/plain', '... and triggers only as requested';
};

test_psgi app => builder {
	enable 'Rewrite', rules => sub {};
	sub { [ 301, [ qw( Location http://localhost/ ) ], [] ] };
}, client => sub {
	my $cb = shift;
	my $res = $cb->( GET 'http://localhost/' );
	ok !$res->content, 'Redirects from the wrapped app are passed through untouched';
};

done_testing;
