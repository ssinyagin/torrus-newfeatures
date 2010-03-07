#  Copyright (C) 2010  Stanislav Sinyagin
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

# Universal CGI handler for Apache mod_perl and FastCGI

package Torrus::CGI;

use strict;
use CGI;
use IO::File;
    
# This modue is not a part of mod_perl
use Apache::Session::File;


use Torrus::Log;
use Torrus::Renderer;
use Torrus::SiteConfig;
use Torrus::ACL;

## Torrus::CGI->process($q)
## Expects a CGI object as input

sub process
{
    my($class, $q) = @_;

    if( $Torrus::Renderer::globalDebug )
    {
        print STDERR $q->Dump();
    }
    
    my @paramNames = $q->param();

    if( $q->param('DEBUG') and not $Torrus::Renderer::globalDebug ) 
    {
        &Torrus::Log::setLevel('debug');
    }

    my %options = ();
    foreach my $name ( @paramNames )
    {
        if( $name =~ /^[A-Z]/ and $name ne 'SESSION_ID' )
        {
            $options{'variables'}->{$name} = $q->param($name);
        }
    }

    my( $fname, $mimetype, $expires );
    my @cookies;

    my $renderer = new Torrus::Renderer();
    if( not defined( $renderer ) )
    {
        return report_error($q, 'Error initializing Renderer');
    }

    my $tree = $q->url(-path => 1);
    $tree =~ s/^.*\/(.*)$/$1/;

    if( $Torrus::ApacheHandler::authorizeUsers )
    {
        my $ses_id = $q->cookie('SESSION_ID');

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

        my %cookie = (-name  => 'SESSION_ID',
                      -value => $session{'_session_id'});

        if( $q->param('remember') )
        {
            $cookie{'-expires'} = '+365d';
        }
            
        push(@cookies, $q->cookie(%cookie));

        $options{'acl'} = new Torrus::ACL;

        if( $session{'uid'} )
        {
            $options{'uid'} = $session{'uid'};
        }
        else
        {
            my $needsLogin = 1;

            # POST form parameters

            my $uid = $q->param('uid');
            my $password = $q->param('password');
            if( defined( $uid ) and defined( $password ) )
            {
                if( $options{'acl'}->authenticateUser( $uid, $password ) )
                {
                    $session{'uid'} = $options{'uid'} = $uid;
                    $needsLogin = 0;
                    Info('User logged in: ' . $uid);
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
                    my $val = $q->param( $param );
                    if( defined( $val ) and length( $val ) > 0 )
                    {
                        $options{'urlPassParams'}{$param} = $val;
                    }
                }
                
                ( $fname, $mimetype, $expires ) =
                    $renderer->renderUserLogin( %options );
                
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
                $renderer->renderTreeChooser( %options );
        }
        else
        {
            if( $Torrus::ApacheHandler::authorizeUsers and
                not $options{'acl'}->hasPrivilege( $options{'uid'}, $tree,
                                                   'DisplayTree' ) )
            {
                return report_error($q, 'Permission denied');
            }
            
            if( $Torrus::Renderer::displayReports and
                defined( $q->param('htmlreport') ) )
            {
                if( $Torrus::ApacheHandler::authorizeUsers and
                    not $options{'acl'}->hasPrivilege( $options{'uid'}, $tree,
                                                       'DisplayReports' ) )
                {
                    return report_error($q, 'Permission denied');
                }

                my $reportfname = $q->param('htmlreport');
                # strip off leading slashes for security
                $reportfname =~ s/^.*\///o;
                
                $fname = $Torrus::Global::reportsDir . '/' . $tree .
                    '/html/' . $reportfname;
                if( not -f $fname )
                {
                    return report_error($q, 'No such file: ' . $reportfname);
                }
                
                $mimetype = 'text/html';
                $expires = '3600';
            }
            else
            {
                my $config_tree = new Torrus::ConfigTree( -TreeName => $tree );
                if( not defined($config_tree) )
                {
                    return report_error($q, 'Configuration is not ready');
                }
                
                my $token = $q->param('token');
                if( not $token )
                {
                    my $path = $q->param('path');
                    $path = '/' unless $path;
                    $token = $config_tree->token($path);
                    if( not $token )
                    {
                        return report_error($q, 'Invalid path');
                    }
                }
                elsif( $token !~ /^S/ and
                       not defined( $config_tree->path( $token ) ) )
                {
                    return report_error($q, 'Invalid token');
                }
                
                my $view = $q->param('view');

                ( $fname, $mimetype, $expires ) =
                    $renderer->render( $config_tree, $token, $view, %options );
                
                undef $config_tree;
            }
        }
    }

    undef $renderer;
    &Torrus::DB::cleanupEnvironment();

    if( defined( $options{'acl'} ) )
    {
        undef $options{'acl'};
    }

    if( defined($fname) )
    {
        if( not -e $fname )
        {
            return report_error($q, 'No such file or directory: ' . $fname);
        }
        
        Debug("Render returned $fname $mimetype $expires");

        my $fh = new IO::File( $fname );
        if( defined( $fh ) )
        {
            print $q->header('-type' => $mimetype,
                             '-expires' => '+'.$expires.'s',
                             '-cookie' => \@cookies);
            
            $fh->binmode(':raw');
            my $buffer;           
            while( $fh->read( $buffer, 65536 ) )
            {
                print( $buffer );
            }
            $fh->close();
        }
        else
        {
            return report_error($q, 'Cannot open file ' . $fname . ': ' . $!);
        }
    }
    else
    {
        return report_error($q, "Renderer returned error.\n" .
                            "Probably wrong directory permissions or " .
                            "directory missing:\n" .
                            $Torrus::Global::cacheDir);            
    }
    
    if( not $Torrus::Renderer::globalDebug )
    {
        &Torrus::Log::setLevel('info');
    }
}


sub report_error
{
    my $q = shift;
    my $msg = shift;

    print $q->header('-type' => 'text/plain',
                     '-expires' => 'now');

    print('Error: ' . $msg);
}


1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End: