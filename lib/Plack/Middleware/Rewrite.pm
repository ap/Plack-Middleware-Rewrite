package Plack::Middleware::Rewrite;
use strict;
use parent qw( Plack::Middleware );

# ABSTRACT: mod_rewrite for Plack

use Plack::Util::Accessor qw( rules );
use Plack::Request ();
use Plack::Util ();
use URI ();

sub call {
	my $self = shift;
	my ( $env ) = @_;

	local $env->{'QUERY_STRING'} = $env->{'QUERY_STRING'};
	local $env->{'PATH_INFO'}    = $env->{'PATH_INFO'};

	my $modify_cb;

	for ( $env->{'PATH_INFO'} ) {
		my $res = $self->rules->( $env ) or last;

		$modify_cb = $res if 'CODE' eq ref $res;

		$res = [ $res ] if not ref $res and $res =~ /\A[1-5][0-9][0-9]\z/;

		last if 'ARRAY' ne ref $res or @$res < 1;

		push @$res, [] if @$res < 2;
		push @$res, [] if @$res < 3;

		if ( $res->[0] =~ /\A3[0-9][0-9]\z/ ) {
			my $req_base = Plack::Request->new( $env )->uri;
			my $abs_dest = URI->new_abs( $_, $req_base );
			Plack::Util::header_set( $res->[1], Location => $abs_dest );
		}

		return $res;
	}

	my $res = $self->app->( $env );
	return $res if not $modify_cb;

	Plack::Util::response_cb( $res, sub {
		$modify_cb->( $env ) for Plack::Util::headers( $_[0][1] );
		return;
	} );
}

1;

__END__

=head1 SYNOPSIS

 # in app.psgi
 use Plack::Builder;
 
 builder {
     enable 'Rewrite', rules => sub {
         s{^/here(?=/|$)}{/there};

         return 301
             if s{^/foo/?$}{/bar/}
             or s{^/baz/?$}{/quux/};

         return 201 if $_ eq '/favicon.ico';

         return [200, [qw(Content-Type text/plain)], ['You found it!']]
            if $_ eq '/easter-egg';

         return sub { $_->set( 'Content-Type', 'application/xhtml+xml' ) }
             if $_[0]{'HTTP_ACCEPT'} =~ m{application/xhtml\+xml(?!\s*;\s*q=0)}
     };
     $app;
 };

=head1 DESCRIPTION

This middleware provides a convenient way to modify requests in flight in Plack
apps. Rewrite rules are simply written in Perl, which means everything that can
be done with mod_rewrite can be done with this middleware much more intuitively
(if in syntactically wordier ways). Its primary purpose is rewriting paths, but
almost anything is possible very easily.

=head1 CONFIGURATIONS

=over 4

=item rules

C<rules> takes a reference to a function that will be called on each request.
When it is, the C<PATH_INFO> is aliased to C<$_>, so that you can easily use
regexp matches and subtitutions to examine and modify it. The L<PSGI>
envrionment will be passed as its first and only argument.

This function can return a value that looks like an HTTP status to stop the
request from being processed further. In that case an empty response with the
returned status will be sent to the browser. If it is a redirect status, then
the rewritten C<PATH_INFO> will be used as the redirect destination.

Alternatively it can return an array: a regular L<PSGI> response, except that
you may omit either or both the headers and body elements. (Empty ones will be
supplied for you, for convenience.)

A third option is to return a reference to a function. This function will
be called I<after> the request has been processed, with C<$_> aliased to a
L<Plack::Util>::headers object for the response, for convenient alteration
of headers. The L<PSGI> environment is, again, passed as its first and only
argument.

=back
