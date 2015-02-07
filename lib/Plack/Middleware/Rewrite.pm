use 5.006;
use strict;
use warnings;

package Plack::Middleware::Rewrite;

# ABSTRACT: mod_rewrite for Plack

use parent 'Plack::Middleware';

use Plack::Util::Accessor 'rules';
use Plack::Request ();
use Plack::Util ();

sub call {
	my $self = shift;
	my ( $env ) = @_;

	my $modify_cb;

	# call rules with $_ aliased to PATH_INFO
	my ( $res ) = map { $self->rules->( $env ) } $env->{'PATH_INFO'};

	# upgrade scalar return value, but only if it looks like an HTTP status
	$res = [ $res, [], [] ]
		if not ref $res
		and defined $res
		and $res =~ /\A[1-5][0-9][0-9]\z/;

	if ( 'ARRAY' eq ref $res and @$res ) { # external redirect, or explicit response
		push @$res, map { [] } @$res .. 2;

		if ( $res->[0] =~ /\A3[0-9][0-9]\z/ ) {
			my $dest = Plack::Util::header_get( $res->[1], 'Location' );
			if ( not $dest ) {
				$dest = Plack::Request->new( $env )->uri;
				Plack::Util::header_set( $res->[1], Location => $dest );
			}

			if ( 304 ne $res->[0] and not (
				Plack::Util::content_length( $res->[2] )
				or Plack::Util::header_exists( $res->[1], 'Content-Length' )
			) ) {
				my $href = Plack::Util::encode_html( $dest );
				Plack::Util::header_set( $res->[1], qw( Content-Type text/html ) );
				$res->[2] = [ qq'<!DOCTYPE html><title>Moved</title>This resource has moved to <a href="$href">a new address</a>.' ];
			}
		}
	}
	else { # internal redirect
		$modify_cb = $res if 'CODE' eq ref $res;
		$res = $self->app->( $env );
	}

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

         return 303
             if s{^/foo/?$}{/bar/}
             or s{^/baz/?$}{/quux/};

         return [301, [ Location => 'http://example.org/' ], []]
             if m{^/example/?$};

         return 201 if $_ eq '/favicon.ico';

         return 503 if -e '/path/to/app/maintenance.lock';

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
environment will be passed as its first and only argument. The function can
return four (and a half) kinds of values:

=over 4

=item Nothing or C<undef>

In that case, any path and query string rewriting will be treated as an
internal rewrite, invisible to the user. This is just like having
C<RewriteRule>s that do not redirect.

=item A scalar value that looks like an HTTP status

This will stop the request from being processed further. An empty response with
the returned status will be sent to the browser. If it is a redirect status,
then the rewritten C<PATH_INFO> will be used as the redirect destination.

Note that this means you can only redirect to other URLs on the same domain.
To redirect to another host entirely, you will need to supply a C<Location>
header manually, which requires returning either an array or code reference.

=item An array reference

This is assumed to be a regular L<PSGI> response, except that you may omit
either or both the headers and body elements. Empty ones will be supplied for
you, for convenience.

=item A code reference

The function you supply will be called I<after> the request has been processed,
with C<$_> aliased to a L<C<Plack::Util::headers>|Plack::Util> object for the
response, for convenient alteration of headers. The L<PSGI> environment is,
again, passed as its first and only argument.

=item Any other kind of value

Other values are currently treated the same as returning nothing. This may
change in the future, depending on whether ambiguities crop up in practice.
If you want to be absolutely certain to avoid ambiguities, return one-element
arrays instead of plain values, and use an explicit C<return> at the end of
your rules:

 return [201] if $_ eq '/favicon.ico';
 s{^/here(?=/|$)}{/there};
 return;

=back

=back
