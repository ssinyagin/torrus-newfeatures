#  Copyright (C) 2002-2011  Stanislav Sinyagin
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

# Stanislav Sinyagin <ssinyagin@k-open.com>

package Torrus::Renderer;
use strict;
use warnings;

use File::Temp qw(tempfile);

use Torrus::ConfigTree;
use Torrus::RPN;
use Torrus::Log;
use Torrus::SiteConfig;

use Torrus::Renderer::HTML;
use Torrus::Renderer::RRDtool;
use Torrus::Renderer::Frontpage;
use Torrus::Renderer::AdmInfo;
use Torrus::Renderer::RPC;
use Torrus::Renderer::Health;

# Inherit methods from these modules
use base qw(Torrus::Renderer::HTML
            Torrus::Renderer::RRDtool
            Torrus::Renderer::Frontpage
            Torrus::Renderer::AdmInfo
            Torrus::Renderer::RPC
            Torrus::Renderer::Health);

sub new
{
    my $self = {};
    my $class = shift;
    bless $self, $class;    
    return $self;
}


# Returns the absolute filename and MIME type:
#
# my($fname, $mimetype) = $renderer->render($config_tree, $token, $view);
#

sub render
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;
    my %new_options = @_;

    # If no options given, preserve the existing ones
    if( %new_options )
    {
        $self->{'options'} = \%new_options;
    }

    my $tree = $config_tree->treeName();

    if( not $config_tree->isTset($token) )
    {
        if( not defined( $config_tree->path($token) ) )
        {
            Error("No such token: $token");
            return undef;
        }
    }

    $view = $config_tree->getDefaultView($token) unless defined $view;

    my $uid = '';
    if( $self->{'options'}->{'uid'} )
    {
        $uid = $self->{'options'}->{'uid'};
    }

    my $method = 'render_' . $config_tree->getOtherParam($view, 'view-type');

    my ($fh, $filename) = tempfile();
    $fh->close();
    
    my ($t_expires, $mime_type) =
        $self->$method( $config_tree, $token, $view, $filename );

    if( %new_options )
    {
        $self->{'options'} = undef;
    }

    my @ret;
    if( defined($t_expires) and defined($mime_type) )
    {
        @ret = ($filename, $mime_type, $t_expires - time());
    }
    else
    {
        unlink $filename;
    }

    return @ret;
}





sub xmlnormalize
{
    my( $txt )= @_;

    # Remove spaces in the head and tail.
    $txt =~ s/^\s+//om;
    $txt =~ s/\s+$//om;

    # Unscreen special characters
    $txt =~ s/{COLON}/:/ogm;
    $txt =~ s/{SEMICOL}/;/ogm;
    $txt =~ s/{PERCENT}/%/ogm;

    $txt =~ s/\&/\&amp\;/ogm;
    $txt =~ s/\</\&lt\;/ogm;
    $txt =~ s/\>/\&gt\;/ogm;
    $txt =~ s/\'/\&apos\;/ogm;
    $txt =~ s/\"/\&quot\;/ogm;

    return $txt;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
