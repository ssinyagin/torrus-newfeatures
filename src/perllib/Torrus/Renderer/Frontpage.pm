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

package Torrus::Renderer::Frontpage;

use strict;

use Torrus::ConfigTree;
use Torrus::RPN;
use Torrus::Log;

use Template;
use URI::Escape;

# All our methods are imported by Torrus::Renderer;

sub renderUserLogin
{
    my $self = shift;
    my %new_options = @_;

    if( %new_options )
    {
        $self->{'options'} = \%new_options;
    }

    my($t_render, $t_expires, $filename, $mime_type);

    my $cachekey = $self->cacheKey( 'LOGINSCREEN' );

    ($t_render, $t_expires, $filename, $mime_type) =
        $self->getCache( $cachekey );

    # We don't check the expiration time for login screen
    if( not defined( $filename ) )
    {
        $filename = Torrus::Renderer::newCacheFileName( $cachekey );
    }

    my $outfile = $Torrus::Global::cacheDir.'/'.$filename;

    $t_expires = time();
    $mime_type = $Torrus::Renderer::LoginScreen::mimeType;
    my $tmplfile = $Torrus::Renderer::LoginScreen::template;

    # Create the Template Toolkit processor once, and reuse
    # it in subsequent render() calls

    if( not defined( $self->{'tt'} ) )
    {
        $self->{'tt'} =
            new Template(INCLUDE_PATH => $Torrus::Global::templateDirs,
                         TRIM => 1);
    }

    my $url = $Torrus::Renderer::rendererURL;
    if( length( $self->{'options'}->{'urlPassTree'} ) > 0 )
    {
        $url .= '/' . $self->{'options'}->{'urlPassTree'};
    }
       
    my $ttvars =
    {
        'url'        => $url,
        'plainURL'   => $Torrus::Renderer::plainURL,
        'style'      => sub { return $self->style($_[0]); },
        'companyName'=> $Torrus::Renderer::companyName,
        'companyURL' => $Torrus::Renderer::companyURL,
        'siteInfo'   => $Torrus::Renderer::siteInfo,
        'version'    => $Torrus::Global::version,
        'xmlnorm'    => \&Torrus::Renderer::xmlnormalize
    };


    # Pass the options from Torrus::Renderer::render() to Template
    while( my( $opt, $val ) = each( %{$self->{'options'}} ) )
    {
        $ttvars->{$opt} = $val;
    }

    my $result = $self->{'tt'}->process( $tmplfile, $ttvars, $outfile );

    undef $ttvars;

    my @ret;
    if( not $result )
    {
        Error("Error while rendering login screen: " .
              $self->{'tt'}->error());
    }
    else
    {
        $self->setCache($cachekey, time(), $t_expires, $filename, $mime_type);
        @ret = ($outfile, $mime_type, $t_expires - time());
    }

    if( %new_options )
    {
        delete( $self->{'options'} );
    }

    return @ret;
}


sub renderTreeChooser
{
    my $self = shift;
    my %new_options = @_;

    if( %new_options )
    {
        $self->{'options'} = \%new_options;
    }

    my($t_render, $t_expires, $filename, $mime_type);

    my $uid = '';
    if( $self->{'options'}->{'uid'} )
    {
        $uid = $self->{'options'}->{'uid'};
    }

    my $cachekey = $self->cacheKey( $uid . ':' . 'TREECHOOSER' );

    ($t_render, $t_expires, $filename, $mime_type) =
        $self->getCache( $cachekey );

    if( defined( $filename ) )
    {
        if( $t_expires >= time() )
        {
            return ($Torrus::Global::cacheDir.'/'.$filename,
                    $mime_type, $t_expires - time());
        }
        # Else reuse the old filename
    }
    else
    {
        $filename = Torrus::Renderer::newCacheFileName( $cachekey );
    }

    my $outfile = $Torrus::Global::cacheDir.'/'.$filename;

    $t_expires = time() + $Torrus::Renderer::Chooser::expires;
    $mime_type = $Torrus::Renderer::Chooser::mimeType;
    my $tmplfile = $Torrus::Renderer::Chooser::template;

    # Create the Template Toolkit processor once, and reuse
    # it in subsequent render() calls

    if( not defined( $self->{'tt'} ) )
    {
        $self->{'tt'} =
            new Template(INCLUDE_PATH => $Torrus::Global::templateDirs,
                         TRIM => 1);
    }

    my $ttvars =
    {
        'treeNames' => sub{ return Torrus::SiteConfig::listTreeNames() },
        'treeDescr' => sub{ return
                                Torrus::SiteConfig::treeDescription($_[0]) },
        'url'  => sub { return $Torrus::Renderer::rendererURL . '/' . $_[0] },
        'plainURL'   => $Torrus::Renderer::plainURL,
        'style'      => sub { return $self->style($_[0]); },
        'companyName'=> $Torrus::Renderer::companyName,
        'companyURL' => $Torrus::Renderer::companyURL,
        'siteInfo'   => $Torrus::Renderer::siteInfo,
        'version'    => $Torrus::Global::version,
        'xmlnorm'    => \&Torrus::Renderer::xmlnormalize,
        'userAuth'   => $Torrus::ApacheHandler::authorizeUsers,
        'uid'        => $self->{'options'}->{'uid'},
        'userAttr'   => sub { return $self->userAttribute( $_[0] ) },
        'mayDisplayTree' => sub { return $self->
                                      hasPrivilege( $_[0], 'DisplayTree' ) }
    };


    # Pass the options from Torrus::Renderer::render() to Template
    while( my( $opt, $val ) = each( %{$self->{'options'}} ) )
    {
        $ttvars->{$opt} = $val;
    }

    my $result = $self->{'tt'}->process( $tmplfile, $ttvars, $outfile );

    undef $ttvars;

    my @ret;
    if( not $result )
    {
        Error("Error while rendering tree chooser: " .
              $self->{'tt'}->error());
    }
    else
    {
        $self->setCache($cachekey, time(), $t_expires, $filename, $mime_type);
        @ret = ($outfile, $mime_type, $t_expires - time());
    }

    if( %new_options )
    {
        delete( $self->{'options'} );
    }

    return @ret;
}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
