#  Copyright (C) 2002  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>

# Apache mod_perl handler. See http://perl.apache.org

package Torrus::Apache2Handler;

use strict;

use Apache2::RequestRec;
use Apache2::RequestIO;
use Apache2::RequestUtil;
use Apache2::Const -compile => qw(:common);
    
# This is actually not a part of mod_perl
use Apache::Session::File;

# libapreq2-2.06 or higher
use Apache2::Request;

use Torrus::Log;
use Torrus::Renderer;
use Torrus::SiteConfig;
use Torrus::ACL;

sub handler : method
{
    my($class, $r) = @_;

    if( $Torrus::Renderer::globalDebug )
    {
        print STDERR $r->as_string();
    }
    
    my $apr = Apache2::Request->new($r);

    my @paramNames = $apr->param();

    if( $apr->param('DEBUG') and not $Torrus::Renderer::globalDebug ) 
    {
        &Torrus::Log::setLevel('debug');
    }

    my %options = ();
    foreach my $name ( @paramNames )
    {
        if( $name =~ /^[A-Z]/ and $name ne 'SESSION_ID' )
        {
            $options{'variables'}->{$name} = $apr->param($name);
        }
    }

    my( $fname, $mimetype, $expires );

    # Create the Renderer instance once and reuse in subsequent handler calls
    if( not defined( $Torrus::ApacheHandler::renderer ) )
    {
        $Torrus::ApacheHandler::renderer = new Torrus::Renderer();
        if( not defined( $Torrus::ApacheHandler::renderer ) )
        {
            return Apache2::Const::SERVER_ERROR;
        }
    }

    my $tree = $r->uri();
    $tree =~ s/^.*\/(.*)$/$1/;

    if( $Torrus::ApacheHandler::authorizeUsers )
    {
        my $ses_id = $r->headers_in->get('Cookie');
        $ses_id =~ s/.*SESSION_ID=(\w*).*/$1/;

        my $needs_new_session = 1;
        my %session;

        if( $ses_id )
        {
            # create a session object based on the cookie we got from the
            # browser, or a new session if we got no cookie
            eval
            {
                tie %session, 'Apache::Session::File', $ses_id, {
                    Directory     => $Torrus::Global::sesStoreDir,
                    LockDirectory => $Torrus::Global::sesLockDir }
            };
            if( not $@ )
            {
                if( $options{'variables'}->{'LOGOUT'} )
                {
                    tied( %session )->delete();
                }
                else
                {
                    $needs_new_session = 0;
                }
            }
        }

        if( $needs_new_session )
        {
            tie %session, 'Apache::Session::File', undef, {
                Directory     => $Torrus::Global::sesStoreDir,
                LockDirectory => $Torrus::Global::sesLockDir };
        }

        # might be a new session, so lets give them their cookie back
        my $session_cookie = 'SESSION_ID=' . $session{'_session_id'} . ';';
        $r->headers_out->add( 'Set-Cookie', $session_cookie );

        $options{'acl'} = new Torrus::ACL;

        if( $session{'uid'} )
        {
            $options{'uid'} = $session{'uid'};
        }
        else
        {
            my $needsLogin = 1;

            # POST form parameters

            my $uid = $apr->param('uid');
            my $password = $apr->param('password');
            if( defined( $uid ) and defined( $password ) )
            {
                if( $options{'acl'}->authenticateUser( $uid, $password ) )
                {
                    $session{'uid'} = $options{'uid'} = $uid;
                    $needsLogin = 0;
                }
                else
                {
                    $options{'authFailed'} = 1;
                }
            }

            if( $needsLogin )
            {
                $options{'urlPassTree'} = $tree;
                foreach my $param ( 'token', 'path', 'view' )
                {
                    my $val = $apr->param( $param );
                    if( defined( $val ) and length( $val ) > 0 )
                    {
                        $options{'urlPassParams'}{$param} = $val;
                    }
                }
                
                ( $fname, $mimetype, $expires ) =
                    $Torrus::ApacheHandler::renderer->
                    renderUserLogin( %options );

                die('renderUserLogin returned undef') unless $fname;
            }
        }
        untie %session;
    }

    if( not $fname )
    {
        if( not $tree or not Torrus::SiteConfig::treeExists( $tree ) )
        {
            ( $fname, $mimetype, $expires ) =
                $Torrus::ApacheHandler::renderer->
                renderTreeChooser( %options );
        }
        else
        {
            if( $Torrus::ApacheHandler::authorizeUsers and
                not $options{'acl'}->hasPrivilege( $options{'uid'}, $tree,
                                                   'DisplayTree' ) )
            {
                return report_error($r, 'Permission denied');
            }

            my $config_tree = new Torrus::ConfigTree( -TreeName => $tree );
            if( not defined($config_tree) )
            {
                return report_error($r, 'Configuration is not ready');
            }

            my $token = $apr->param('token');
            if( not $token )
            {
                my $path = $apr->param('path');
                $path = '/' unless $path;
                $token = $config_tree->token($path);
                if( not $token )
                {
                    return report_error($r, 'Invalid path');
                }
            }
            elsif( $token !~ /^S/ and
                   not defined( $config_tree->path( $token ) ) )
            {
                return report_error($r, 'Invalid token');
            }

            my $view = $apr->param('view');

            ( $fname, $mimetype, $expires ) =
                $Torrus::ApacheHandler::renderer->
                render( $config_tree, $token, $view, %options );

            undef $config_tree;
        }
    }

    if( defined( $options{'acl'} ) )
    {
        undef $options{'acl'};
    }

    my $retval = Apache2::Const::OK;

    if( defined($fname) )
    {
        Debug("Render returned $fname $mimetype $expires");

        $r->headers_out->add( 'Expires', '+'.$expires.'s' );
        if( index( $mimetype, 'text' ) >= 0 and $expires > 0 )
        {
            $r->headers_out->add( 'Refresh', $expires );
        }
        $r->content_type( $mimetype );
        $r->sendfile( $fname );
    }
    else
    {
        $retval = Apache2::Const::SERVER_ERROR;
    }
    
    if( not $Torrus::Renderer::globalDebug )
    {
        &Torrus::Log::setLevel('warn');
    }
    
    return $retval;
}


sub report_error
{
    my $r = shift;
    my $msg = shift;
    
    $r->no_cache(1);
    $r->content_type('text/plain');
    $r->print('Error: ' . $msg);
    return Apache2::Const::OK;
}


1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
