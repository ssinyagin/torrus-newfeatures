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

package Torrus::ApacheHandler;

use strict;
use Apache;

use Apache::File;

# This is actually not a part of mod_perl
use Apache::Session::File;

use Torrus::Log;
use Torrus::Renderer;
use Torrus::SiteConfig;
use Torrus::ACL;

sub handler
{
    my $r = shift;

    if( $Torrus::Renderer::globalDebug )
    {
        print STDERR $r->as_string();
    }
        
    my %args = $r->args();

    if( $args{'DEBUG'} and not $Torrus::Renderer::globalDebug )
    {
        &Torrus::Log::setLevel('debug');
    }

    my %options = ();
    foreach my $name ( keys %args )
    {
        if( $name =~ /^[A-Z]/ )
        {
            $options{'variables'}->{$name} = $args{$name};
        }
    }

    my( $fname, $mimetype, $expires );

    # Create the Renderer instance once and reuse in subsequent handler calls
    if( not defined( $Torrus::ApacheHandler::renderer ) )
    {
        $Torrus::ApacheHandler::renderer = new Torrus::Renderer();
        if( not defined( $Torrus::ApacheHandler::renderer ) )
        {
            return Apache::Constants::SERVER_ERROR;
        }
    }

    my $tree = $r->uri();
    $tree =~ s/^.*\/(.*)$/$1/;

    if( $Torrus::ApacheHandler::authorizeUsers )
    {
        my $ses_id = $r->header_in('Cookie');
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
        $r->header_out( 'Set-Cookie' => $session_cookie );

        $options{'acl'} = new Torrus::ACL;

        if( $session{'uid'} )
        {
            $options{'uid'} = $session{'uid'};
        }
        else
        {
            my $needsLogin = 1;

            # POST form parameters
            %args = $r->content();

            if( $args{'uid'} and $args{'password'} )
            {
                if( $options{'acl'}->authenticateUser( $args{'uid'},
                                                       $args{'password'} ) )
                {
                    $session{'uid'} = $options{'uid'} = $args{'uid'};
                    $needsLogin = 0;
                    Info('User logged in: ' . $args{'uid'});
                }
                else
                {
                    $options{'authFailed'} = 1;
                }
            }

            if( $needsLogin )
            {
                $options{'urlPassTree'} = $tree;
                my %urlArgs = $r->args();

                if( %urlArgs )
                {
                    foreach my $param ( 'token', 'path', 'view' )
                    {
                        my $val = $urlArgs{$param};
                        if( defined( $val ) and length( $val ) > 0 )
                        {
                            $options{'urlPassParams'}{$param} = $val;
                        }
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

            if( $Torrus::Renderer::displayReports and
                defined( $args{'htmlreport'} ) )
            {
                if( $Torrus::ApacheHandler::authorizeUsers and
                    not $options{'acl'}->hasPrivilege( $options{'uid'}, $tree,
                                                       'DisplayReports' ) )
                {
                    return report_error($r, 'Permission denied');
                }

                my $reportfname = $args{'htmlreport'};
                # strip off leading slashes for security
                $reportfname =~ s/^.*\///o;
                
                $fname = $Torrus::Global::reportsDir . '/' . $tree .
                    '/html/' . $reportfname;
                if( not -f $fname )
                {
                    return report_error($r, 'No such file: ' . $reportfname);
                }
                
                $mimetype = 'text/html';
                $expires = '3600';
            }
            else
            {
                my $config_tree = new Torrus::ConfigTree( -TreeName => $tree );
                if( not defined($config_tree) )
                {
                    return report_error($r, 'Configuration is not ready');
                }
                
                my $token = $args{'token'};
                if( not $token )
                {
                    my $path = $args{'path'};
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
                
                my $view = $args{'view'};

                ( $fname, $mimetype, $expires ) =
                    $Torrus::ApacheHandler::renderer->
                    render( $config_tree, $token, $view, %options );

                undef $config_tree;
            }
        }
    }

    &Torrus::DB::cleanupEnvironment();
    
    if( defined( $options{'acl'} ) )
    {
        undef $options{'acl'};
    }

    my $retval = Apache::Constants::OK;

    if( defined($fname) )
    {
        if( not -e $fname )
        {
            return report_error($r, 'No such file or directory: ' . $fname);
        }
        
        Debug("Render returned $fname $mimetype $expires");

        my $fh = new Apache::File( $fname );
        if( not $fh )
        {
            Error("Cannot open $fname: $!");
            $retval = Apache::Constants::SERVER_ERROR;
        }
        else
        {
            $r->header_out( 'Expires', '+'.$expires.'s' );
            if( index( $mimetype, 'text' ) >= 0 and $expires > 0 )
            {
                $r->header_out( 'Refresh', $expires );
            }
            $r->send_http_header( $mimetype );

            $r->send_fd( $fh );
            $fh->close();
        }
    }
    else
    {
        return report_error($r, "Renderer returned error.\n" .
                            "Probably wrong directory permissions or " .
                            "directory missing:\n" .
                            $Torrus::Global::cacheDir);            
    }

    &Torrus::Log::setLevel('info');
    return $retval;
}


sub report_error
{
    my $r = shift;
    my $msg = shift;
    
    $r->no_cache(1);
    $r->send_http_header('text/plain');
    $r->print('Error: ' . $msg);
    return Apache::Constants::OK;
}


1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
