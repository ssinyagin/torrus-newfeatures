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
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>


package Torrus::ConfigTree::XMLCompiler;

use Torrus::ConfigTree::Writer;
our @ISA=qw(Torrus::ConfigTree::Writer);

use Torrus::ConfigTree;
use Torrus::ConfigTree::Validator;
use Torrus::SiteConfig;
use Torrus::Log;
use Torrus::TimeStamp;

use XML::LibXML;
use strict;

sub new
{
    my $proto = shift;
    my %options = @_;
    my $class = ref($proto) || $proto;

    $options{'-Rebuild'} = 1;

    my $self  = $class->SUPER::new( %options );
    bless $self, $class;

    if( $options{'-NoDSRebuild'} )
    {
        $self->{'-NoDSRebuild'} = 1;
    }

    $self->{'files_processed'} = {};

    return $self;
}


sub compile
{
    my $self = shift;
    my $filename = shift;

    $filename = Torrus::SiteConfig::findXMLFile($filename);
    if( not defined( $filename ) )
    {
        return 0;
    }
                    
    # Make sure we process each file only once
    if( $self->{'files_processed'}{$filename} )
    {
        return 1;
    }
    else
    {
        $self->{'files_processed'}{$filename} = 1;
    }

    Verbose('Compiling ' . $filename);

    my $ok = 1;
    my $parser = new XML::LibXML;
    my $doc;
    eval { $doc = $parser->parse_file( $filename );  };
    if( $@ )
    {
        Error("Failed to parse $filename: $@");
        return 0;
    }

    my $root = $doc->documentElement();

    # Initialize the '/' element
    $self->initRoot();

    my $node;

    # First of all process all pre-required files
    foreach $node ( $root->getElementsByTagName('include') )
    {
        my $incfile = $node->getAttribute('filename');
        if( not $incfile )
        {
            Error("No filename given in include statement in $filename");
            $ok = 0;
        }
        else
        {
            $ok = $self->compile( $incfile ) ? $ok:0;
        }
    }

    if( not $self->{'-NoDSRebuild'} )
    {
        foreach $node ( $root->getElementsByTagName('definitions') )
        {
            $ok = $self->compile_definitions( $node ) ? $ok:0;
        }

        foreach $node ( $root->getElementsByTagName('datasources') )
        {
            $ok = $self->compile_ds( $node ) ? $ok:0;
        }
    }

    foreach $node ( $root->getElementsByTagName('monitors') )
    {
        $ok = $self->compile_monitors( $node ) ? $ok:0;
    }

    foreach $node ( $root->getElementsByTagName('token-sets') )
    {
        $ok = $self->compile_tokensets( $node ) ? $ok:0;
    }

    foreach $node ( $root->getElementsByTagName('views') )
    {
        $ok = $self->compile_views( $node ) ? $ok:0;
    }

    return $ok;
}


sub compile_definitions
{
    my $self = shift;
    my $node = shift;
    my $ok = 1;

    foreach my $def ( $node->getChildrenByTagName('def') )
    {
        my $name = $def->getAttribute('name');
        my $value = $def->getAttribute('value');
        if( not $name )
        {
            Error("Definition without a name"); $ok = 0;
        }
        elsif( not $value )
        {
            Error("Definition without value: $name"); $ok = 0;
        }
        elsif( defined $self->getDefinition($name) )
        {
            Error("Duplicate definition: $name"); $ok = 0;
        }
        else
        {
            $self->addDefinition($name, $value);
        }
    }
    return $ok;
}


# Process <param name="name" value="value"/> and put them into DB.
# Usage: $self->compile_params($node, $name);

sub compile_params
{
    my $self = shift;
    my $node = shift;
    my $name = shift;
    my $isDS = shift;

    my $ok = 1;
    foreach my $p_node ( $node->getChildrenByTagName('param') )
    {
        my $param = $p_node->getAttribute('name');
        my $value = $p_node->getAttribute('value');
        if( not defined($value) )
        {
            $value = $p_node->textContent();
        }
        if( not $param )
        {
            Error("Parameter without name in $name"); $ok = 0;
        }
        else
        {
            # Remove spaces in the head and tail.
            $value =~ s/^\s+//;
            $value =~ s/\s+$//;

            if( $param eq 'legend' )
            {
                # Remove space around delimiters
                $value =~ s/\s*\:\s*/\:/g;
                $value =~ s/\s*\;\s*/\;/g;
            }
            elsif( $param eq 'ds-type' and $value eq 'RRDfile' )
            {
                $value = 'rrd-file';
            }

            if( $isDS )
            {
                $self->setNodeParam($name, $param, $value);
            }
            else
            {
                $self->setParam($name, $param, $value);
            }
        }
    }
    return $ok;
}


sub compile_ds
{
    my $self = shift;
    my $ds_node = shift;
    my $ok = 1;

    # First, process templates. We expect them to be direct children of
    # <datasources>

    foreach my $template ( $ds_node->getChildrenByTagName('template') )
    {
        my $name = $template->getAttribute('name');
        if( not $name )
        {
            Error("Template without a name"); $ok = 0;
        }
        elsif( defined $self->{'Templates'}->{$name} )
        {
            Error("Duplicate template names: $name"); $ok = 0;
        }
        else
        {
            $self->{'Templates'}->{$name} = $template;
        }
    }

    # Recursively traverse the tree
    $ok = $self->compile_subtrees( $ds_node, $self->token('/') ) ? $ok:0;

    return $ok;
}



sub expand_name
{
    my $self = shift;
    my $parentpath = shift;
    my $childname = shift;
    if( index($childname, '$PARENT') > -1 )
    {
        my @pathparts = split('/', $parentpath);
        my $parentname = pop @pathparts;
        $childname =~ s/\$PARENT/$parentname/g;
    }
    return $childname;
}

sub validate_nodename
{
    my $self = shift;
    my $name = shift;

    return ( $name =~ /^[0-9A-Za-z_\-\.]+$/ and
             $name !~ /\.\./ );
}

sub compile_subtrees
{
    my $self = shift;
    my $node = shift;
    my $token = shift;
    my $ok = 1;

    my $path = $self->path($token);
    my $iamLeaf = $node->nodeName() eq 'leaf';

    # Apply templates

    foreach my $templateapp ( $node->getChildrenByTagName('apply-template') )
    {
        my $name = $templateapp->getAttribute('name');
        if( not $name )
        {
            Error("Template application without a name at $path"); $ok = 0;
        }
        else
        {
            my $template = $self->{'Templates'}->{$name};
            if( not defined $template )
            {
                Error("Cannot find template named $name at $path"); $ok = 0;
            }
            else
            {
                $ok = $self->compile_subtrees( $template, $token ) ? $ok:0;
            }
        }
    }

    $ok = $self->compile_params($node, $token, 1);

    # Handle aliases -- we are still in compile_subtrees()

    foreach my $alias ( $node->getChildrenByTagName('alias') )
    {
        my $apath = $alias->textContent();
        $apath =~ s/\s+//mg;
        $ok = $self->setAlias($token, $apath) ? $ok:0;
    }

    # Handle file patterns -- we're still in compile_subtrees()

    foreach my $fp ( $node->getChildrenByTagName('filepattern') )
    {
        my $type = $fp->getAttribute('type');
        my $name = $fp->getAttribute('name');
        my $file_re = $fp->getAttribute('filere');
        my $dirname = $self->getNodeParam($token, 'data-dir');

        if($type ne 'subtree' and $type ne 'leaf')
        {
            Error("Unknown filepattern type: $type at $path"); $ok = 0;
        }
        elsif( not defined($name) or not defined($file_re) )
        {
            Error("Filepattern name or RE not defined at $path"); $ok = 0;
        }
        elsif( not defined($dirname) )
        {
            Error("data-dir parameter not defined at $path"); $ok = 0;
        }
        elsif( not -d $dirname )
        {
            Error("Directory $dirname does not exist at $path"); $ok = 0;
        }
        else
        {
            $file_re = $self->expand_name($path, $file_re);

            # Read the directory and match the pattern
            my %applied = ();
            opendir(DIR, $dirname) or die "can't opendir $dirname: $!";
            while( (my $fname = readdir(DIR)) )
            {
                if( $fname =~ /$file_re/ )
                {
                    my $newnodename = eval($name);
                    if( defined $applied{$newnodename} )
                    {
                        Error("Filepattern gives non-unique names: " .
                              "name=\"$name\" filere=\"$file_re\" at $path");
                        $ok = 0;
                    }
                    else
                    {
                        $applied{$newnodename} = $fname;
                    }
                }
            }
            closedir DIR;
            # Clone the contents of filepattern into the main tree
            my %detailedmatched = ();
            foreach my $newnodename (keys %applied)
            {
                my $newnode = XML::LibXML::Element->new( $type );
                $newnode->setAttribute('name', $newnodename);
                $node->parentNode()->appendChild($newnode);

                my $childname = $newnodename;
                $childname .= '/' if $type eq 'subtree';
                my $newnodetoken = $self->addChild($token, $childname);
                my $newnodepath = $path.$childname;

                $self->setNodeParam($newnodetoken, 'data-file',
                                $applied{$newnodename});

                foreach my $fpchild ($fp->childNodes())
                {
                    if( $fpchild->nodeName() eq 'detailed' )
                    {
                        my $match =  $fpchild->getAttribute('match');
                        if( not defined $match )
                        {
                            Error("Detailed should have match at $path");
                            $ok = 0;
                        }
                        else
                        {
                            if( not defined $detailedmatched{$match} )
                            {
                                $detailedmatched{$match} = 0;
                            }
                            if( $match eq $newnodename )
                            {
                                $detailedmatched{$match} = 1;
                                foreach my $detnode ( $fpchild->childNodes() )
                                {
                                    $newnode->
                                        appendChild($detnode->cloneNode(1));
                                }
                            }
                        }
                    }
                    else
                    {
                        $newnode->appendChild($fpchild->cloneNode(1));
                    }
                }
                $ok = $self->
                    compile_subtrees( $newnode, $newnodetoken ) ? $ok:0;
            }

            # Check if any of detailed have not matched

            foreach my $match (keys %detailedmatched)
            {
                if( not $detailedmatched{$match} )
                {
                    Warn("Detailed match \"$match\" have not matched any ".
                         "file at $path");
                }
            }
        }
    }

    foreach my $setvar ( $node->getChildrenByTagName('setvar') )        
    {
        my $name = $setvar->getAttribute('name');
        my $value = $setvar->getAttribute('value');
        if( not defined( $name ) or not defined( $value ) )
        {
            Error("Setvar statement without name or value in $path"); $ok = 0;
        }
        else
        {
            $self->setVar( $token, $name, $value );
        }
    }

    # Compile-time variables
    
    foreach my $iftrue ( $node->getChildrenByTagName('iftrue') )        
    {
        my $var = $iftrue->getAttribute('var');
        if( not defined( $var ) )
        {
            Error("Iftrue statement without variable name in $path"); $ok = 0;
        }
        elsif( $self->isTrueVar( $token, $var ) )
        {
            $ok = $self->compile_subtrees( $iftrue, $token ) ? $ok:0;
        }
    }

    foreach my $iffalse ( $node->getChildrenByTagName('iffalse') )        
    {
        my $var = $iffalse->getAttribute('var');
        if( not defined( $var ) )
        {
            Error("Iffalse statement without variable name in $path"); $ok = 0;
        }
        elsif( not $self->isTrueVar( $token, $var ) )
        {
            $ok = $self->compile_subtrees( $iffalse, $token ) ? $ok:0;
        }
    }

    
    # Compile child nodes -- the last part of compile_subtrees()

    if( not $iamLeaf )
    {
        foreach my $subtree ( $node->getChildrenByTagName('subtree') )
        {
            my $name = $subtree->getAttribute('name');
            if( not defined( $name ) or length( $name ) == 0 )
            {
                Error("Subtree without a name at $path"); $ok = 0;
            }
            else
            {
                $name = $self->expand_name( $path, $name );
                if( $self->validate_nodename( $name ) )
                {
                    my $stoken = $self->addChild($token, $name.'/');
                    $ok = $self->compile_subtrees( $subtree, $stoken ) ? $ok:0;
                }
                else
                {
                    Error("Invalid subtree name: $name at $path"); $ok = 0;
                }
            }
        }

        foreach my $leaf ( $node->getChildrenByTagName('leaf') )
        {
            my $name = $leaf->getAttribute('name');
            if( not defined( $name ) or length( $name ) == 0 )
            {
                Error("Leaf without a name at $path"); $ok = 0;
            }
            else
            {
                $name = $self->expand_name( $path, $name );
                if( $self->validate_nodename( $name ) )
                {
                    my $ltoken = $self->addChild($token, $name);
                    $ok = $self->compile_subtrees( $leaf, $ltoken ) ? $ok:0;
                }
                else
                {
                    Error("Invalid leaf name: $name at $path"); $ok = 0;
                }
            }
        }
    }
    return $ok;
}


sub compile_monitors
{
    my $self = shift;
    my $mon_node = shift;
    my $ok = 1;

    foreach my $monitor ( $mon_node->getChildrenByTagName('monitor') )
    {
        my $mname = $monitor->getAttribute('name');
        if( not $mname )
        {
            Error("Monitor without a name"); $ok = 0;
        }
        else
        {
            $ok = $self->addMonitor( $mname );
            $ok = $self->compile_params($monitor, $mname) ? $ok:0;
        }
    }

    foreach my $action ( $mon_node->getChildrenByTagName('action') )
    {
        my $aname = $action->getAttribute('name');
        if( not $aname )
        {
            Error("Action without a name"); $ok = 0;
        }
        else
        {
            $self->addAction( $aname );
            $ok = $self->compile_params($action, $aname);
        }
    }
    return $ok;
}


sub compile_tokensets
{
    my $self = shift;
    my $tsets_node = shift;
    my $ok = 1;

    $ok = $self->compile_params($tsets_node, 'SS') ? $ok:0;

    foreach my $tokenset ( $tsets_node->getChildrenByTagName('token-set') )
    {
        my $sname = $tokenset->getAttribute('name');
        if( not $sname )
        {
            Error("Token-set without a name"); $ok = 0;
        }
        else
        {
            $sname = 'S'. $sname;
            $ok = $self->addTset( $sname );
            $ok = $self->compile_params($tokenset, $sname) ? $ok:0;
        }
    }
    return $ok;
}


sub compile_views
{
    my $self = shift;
    my $vw_node = shift;
    my $parentname = shift;
    my $ok = 1;

    foreach my $view ( $vw_node->getChildrenByTagName('view') )
    {
        my $vname = $view->getAttribute('name');
        if( not $vname )
        {
            Error("View without a name"); $ok = 0;
        }
        else
        {
            $self->addView( $vname, $parentname );
            $ok = $self->compile_params( $view, $vname ) ? $ok:0;
            # Process child views
            $ok = $self->compile_views( $view, $vname ) ? $ok:0;
        }
    }
    return $ok;
}



1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
