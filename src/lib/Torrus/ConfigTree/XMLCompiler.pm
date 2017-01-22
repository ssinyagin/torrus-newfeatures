#  Copyright (C) 2002-2017  Stanislav Sinyagin
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


package Torrus::ConfigTree::XMLCompiler;

use strict;
use warnings;

use base 'Torrus::ConfigTree::Writer';

use Torrus::ConfigTree;
use Torrus::ConfigTree::Validator;
use Torrus::SiteConfig;
use Torrus::Log;

use XML::LibXML;

sub new
{
    my $proto = shift;
    my %options = @_;
    my $class = ref($proto) || $proto;

    $options{'-Rebuild'} = 1;

    my $self  = $class->SUPER::new( %options );
    if( not defined( $self ) )
    {
        return undef;
    }

    bless $self, $class;

    return $self;
}


sub _preprocess_file
{
    my $self = shift;
    my $filename = shift;
    
    # Make sure we process each file only once
    if( $self->{'srcfiles_seen'}{$filename} )
    {
        return 1;
    }

    my $fullname = Torrus::SiteConfig::findXMLFile($filename);
    if( not defined( $fullname ) )
    {
        return 0; # fatal, cannot find the file
    }
    
    $self->{'srcfiles_seen'}{$filename} = 1;
    
    Verbose('Reading ' . $fullname);
    open(my $fh, '<:raw:encoding(utf8)', $fullname) or
        die("Cannot open $fullname: $!");
    my $blob = do { local $/; <$fh> };
    close($fh);
    
    my $file_changed = $self->addSrcFile($filename, \$blob);
    if( $file_changed )
    {
        Debug('File changed: ' . $fullname);
        my $parser = new XML::LibXML;
        my $doc;
        
        if( not eval {$doc = $parser->parse_string(\$blob)} or $@ )
        {
            Error("Failed to parse $fullname: $@");
            return 0;
        }
        
        # clean up the memory
        $blob = undef;

        my $root = $doc->documentElement();
        $self->clearSrcIncludes($filename);
        
        foreach my $node ( $root->getElementsByTagName('include') )
        {
            my $incfile = $node->getAttribute('filename');
            if( not $incfile )
            {
                Error("No filename given in include statement in $fullname");
                return 0;
            }

            if( not $self->_preprocess_file($incfile) )
            {
                return 0;
            }
            
            $self->addSrcInclude($filename, $incfile);
        }

        # param properties and definitions are global for the whole tree
        if( $root->getElementsByTagName('param-properties')->size() > 0 or
            $root->getElementsByTagName('definitions')->size() > 0 )
        {
            $self->setSrcGlobalDep($filename);
        }

        foreach my $node ( $root->getElementsByTagName('datasources') )
        {
            if( $node->getChildrenByTagName('template')->size() > 0 )
            {
                # Whenever there's a temlate, we mark the file as global
                # dependency
                $self->setSrcGlobalDep($filename);
            }
        }
    }
    else
    {
        # clean up the memory
        $blob = undef;

        foreach my $incfile ($self->getSrcIncludes($filename))
        {
            if( not $self->_preprocess_file($incfile) )
            {
                return 0;
            }
        }
    }

    return 1;
}
            
        
        
    
sub compile_files
{
    my $self = shift;
    my $srcfiles = shift;

    # First step: process file inclusions and detect changes

    $self->clearSrcIncludes('__ROOT__');
    foreach my $filename (@{$srcfiles})
    {
        if( not $self->_preprocess_file($filename) )
        {
            return 0;
        }
        
        $self->addSrcInclude('__ROOT__', $filename);
    }

    my $rebuild_list = $self->analyzeSrcUpdates();
    my %seen;
    foreach my $filename (@{$rebuild_list})
    {
        if( not $seen{$filename} )
        {
            if( not $self->_compile_file($filename) )
            {
                return 0;
            }
            $seen{$filename} = 1;
        }
    }

    return 1;
}
   

sub _compile_file
{
    my $self = shift;
    my $filename = shift;

    Debug('Compiling file: ' . $filename);
    my $parser = new XML::LibXML;
    
    my $blob = $self->readSrcFile($filename);
    my $doc = $parser->parse_string(\$blob);
    my $root = $doc->documentElement();

    $self->startSrcFileProcessing($filename);
    $self->{'current_srcfile'} = $filename;

    foreach my $node ( $root->getElementsByTagName('param-properties') )
    {
        if( not $self->compile_paramprops($node) )
        {
            return 0;
        }
    }
    foreach my $node ( $root->getElementsByTagName('definitions') )
    {
        if( not $self->compile_definitions($node) )
        {
            return 0;
        }
    }
    
    foreach my $node ( $root->getElementsByTagName('datasources') )
    {
        if( not $self->compile_ds($node) )
        {
            return 0;
        }
    }
        
    foreach my $node ( $root->getElementsByTagName('monitors') )
    {
        if( not $self->compile_monitors($node) )
        {
            return 0;
        }
    }
    
    foreach my $node ( $root->getElementsByTagName('token-sets') )
    {
        if( not $self->compile_tokensets($node) )
        {
            return 0;
        }
    }
    
    $self->startEditingOthers('__VIEWS__');
    
    foreach my $node ( $root->getElementsByTagName('views') )
    {
        if( not $self->compile_views( $node ) )
        {
            return 0;
        }
    }

    $self->endEditingOthers();
    $self->endSrcFileProcessing($filename);

    return 1;
}


sub compile_definitions
{
    my $self = shift;
    my $node = shift;
    
    foreach my $def ( $node->getChildrenByTagName('def') )
    {
        my $name = $def->getAttribute('name');
        my $value = $def->getAttribute('value');
        if( not $name )
        {
            Error("Definition without a name");
            return 0;
        }
        elsif( not $value )
        {
            Error("Definition without value: $name");
            return 0;
        }
        else
        {
            $self->addDefinition($name, $value);
        }
    }
    return 1;
}


sub compile_paramprops
{
    my $self = shift;
    my $node = shift;

    foreach my $def ( $node->getChildrenByTagName('prop') )
    {
        my $param = $def->getAttribute('param'); 
        my $prop = $def->getAttribute('prop');
        my $value = $def->getAttribute('value');
        if( not $param or not $prop or not defined($value) )
        {
            Error("Property definition error");
            return 0;
        }
        else
        {
            $self->setParamProperty($param, $prop, $value);
        }
    }
    return 1;
}



# Process <param name="name" value="value"/> and put them into DB.
# Usage: $self->compile_params($node, $name);

sub compile_params
{
    my $self = shift;
    my $node = shift;
    my $name = shift;
    my $isDS = shift;

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
            Error("Parameter without name in $name");
            return 0;
        }
        else
        {
            # Remove spaces in the head and tail.
            $value =~ s/^\s+//om;
            $value =~ s/\s+$//om;

            if( $isDS )
            {
                $self->setNodeParam($param, $value);
            }
            else
            {
                $self->setOtherParam($param, $value);
            }
        }
    }
    return 1;
}


sub compile_ds
{
    my $self = shift;
    my $ds_node = shift;

    # First, process templates. We expect them to be direct children of
    # <datasources>

    foreach my $template ( $ds_node->getChildrenByTagName('template') )
    {
        my $name = $template->getAttribute('name');
        if( not $name )
        {
            Error("Template without a name");
            return 0;
        }
        elsif( defined $self->{'Templates'}->{$name} )
        {
            Error("Duplicate template names: $name");
            return 0;
        }
        else
        {
            $self->{'Templates'}{$name} = $template;
        }
    }

    # Recursively traverse the tree
    if( not $self->compile_subtrees( $ds_node, '/' ) )
    {
        return 0;
    }

    # last compiled node needs a commit
    $self->commitNode();

    return 1;
}




sub validate_nodename
{
    my $self = shift;
    my $name = shift;

    return ( $name =~ /^[0-9A-Za-z_\-\.\:]+$/o and
             $name !~ /\.\./o );
}


sub compile_subtrees
{
    my $self = shift;
    my $node = shift;
    my $path = shift;
    my $iamLeaf = shift;

    my $token = $self->editNode($path);

    # setting of compile-time variables    
    foreach my $setvar ( $node->getChildrenByTagName('setvar') )        
    {
        my $name = $setvar->getAttribute('name');
        my $value = $setvar->getAttribute('value');
        if( not defined( $name ) or not defined( $value ) )
        {
            Error("Setvar statement without name or value in $path");
            return 0;
        }
        else
        {
            $self->setVar( $token, $name, $value );
        }
    }

    # Apply templates

    foreach my $templateapp ( $node->getChildrenByTagName('apply-template') )
    {
        my $name = $templateapp->getAttribute('name');
        if( not $name )
        {
            Error("Template application without a name at $path");
            return 0;
        }
        else
        {
            my $template = $self->{'Templates'}->{$name};
            if( not defined $template )
            {
                Error("Cannot find template named $name at $path");
                return 0;
            }
            else
            {
                if( not $self->compile_subtrees($template, $path, $iamLeaf) )
                {
                    return 0;
                }
            }
        }
    }

    # templates might include child nodes, so we open this one again
    $self->editNode($path);
    
    if( not $self->compile_params($node, $token, 1) )
    {
        return 0;
    }

    # applying compile-time variables
    
    foreach my $iftrue ( $node->getChildrenByTagName('iftrue') )        
    {
        my $var = $iftrue->getAttribute('var');
        if( not defined( $var ) )
        {
            Error("Iftrue statement without variable name in $path");
            return 0;
        }
        elsif( $self->isTrueVar( $token, $var ) )
        {
            if( not $self->compile_subtrees( $iftrue, $path, $iamLeaf ) )
            {
                return 0;
            }
        }
    }
    
    foreach my $iffalse ( $node->getChildrenByTagName('iffalse') )        
    {
        my $var = $iffalse->getAttribute('var');
        if( not defined( $var ) )
        {
            Error("Iffalse statement without variable name in $path");
            return 0;
        }
        elsif( not $self->isTrueVar( $token, $var ) )
        {
            if( not $self->compile_subtrees( $iffalse, $path, $iamLeaf ) )
            {
                return 0;
            }
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
                Error("Subtree without a name at $path");
                return 0;
            }
            else
            {
                if( $self->validate_nodename( $name ) )
                {
                    if( not $self->compile_subtrees($subtree, $path.$name.'/') )
                    {
                        return 0;
                    }
                }
                else
                {
                    Error("Invalid subtree name: $name at $path");
                    return 0;
                }
            }
        }

        foreach my $leaf ( $node->getChildrenByTagName('leaf') )
        {
            my $name = $leaf->getAttribute('name');
            if( not defined( $name ) or length( $name ) == 0 )
            {
                Error("Leaf without a name at $path");
                return 0;
            }
            else
            {
                if( $self->validate_nodename( $name ) )
                {
                    if( not $self->compile_subtrees(
                            $leaf, $path.$name, 1) )
                    {
                        return 0;
                    }
                }
                else
                {
                    Error("Invalid leaf name: $name at $path");
                    return 0;
                }
            }
        }
    }
    
    return 1;
}



sub compile_monitors
{
    my $self = shift;
    my $mon_node = shift;

    $self->startEditingOthers('__MONITORS__');
    
    foreach my $monitor ( $mon_node->getChildrenByTagName('monitor') )
    {
        my $mname = $monitor->getAttribute('name');
        if( not $mname )
        {
            Error("Monitor without a name");
            return 0;
        }
        else
        {
            $self->addOtherObject($mname);
            if( not $self->compile_params($monitor, $mname) )
            {
                return 0;
            }
            $self->commitOther();
        }
    }

    $self->endEditingOthers();
    $self->startEditingOthers('__ACTIONS__');
    
    foreach my $action ( $mon_node->getChildrenByTagName('action') )
    {
        my $aname = $action->getAttribute('name');
        if( not $aname )
        {
            Error("Action without a name");
            return 0;
        }
        else
        {
            $self->addOtherObject($aname);
            if( not $self->compile_params($action, $aname) )
            {
                return 0;
            }
            $self->commitOther();
        }
    }

    $self->endEditingOthers();

    return 1;
}


sub compile_tokensets
{
    my $self = shift;
    my $tsets_node = shift;

    $self->editOther('SS');
    if( not $self->compile_params($tsets_node, 'SS') )
    {
        return 0;
    }
    $self->commitOther();

    foreach my $tokenset ( $tsets_node->getChildrenByTagName('token-set') )
    {
        my $sname = $tokenset->getAttribute('name');
        if( not $sname )
        {
            Error("Tokenset without a name");
            return 0;
        }
        else
        {
            $sname = 'S'. $sname;
            $self->addTset( $sname );
            $self->editOther($sname);
            if( not $self->compile_params($tokenset, $sname) )
            {
                return 0;
            }
            $self->commitOther();
        }
    }
    return 1;
}


sub compile_views
{
    my $self = shift;
    my $vw_node = shift;
    my $parentname = shift;
    
    foreach my $view ( $vw_node->getChildrenByTagName('view') )
    {
        my $vname = $view->getAttribute('name');
        if( not $vname )
        {
            Error("View without a name");
            return 0;
        }
        else
        {
            $self->addView( $vname, $parentname );
            if( not $self->compile_params( $view, $vname ) )
            {
                return 0;
            }
            $self->commitOther();
            
            # Process child views
            if( not $self->compile_views( $view, $vname ) )
            {
                return 0;
            }
        }
    }
    return 1;
}



1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
