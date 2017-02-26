#  Copyright (C) 2002-2007  Stanislav Sinyagin
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

#
# Write access for ConfigTree
#

package Torrus::ConfigTree::Writer;

use strict;
use warnings;

use base 'Torrus::ConfigTree';

use Torrus::Log;
use Torrus::SiteConfig;
use Torrus::ServiceID;
use Torrus::ConfigTree::Validator;

use Git::ObjectStore;
use Git::Raw;

use Digest::MD5 qw(md5); # needed as hash function
use POSIX; # we use ceil() from here
use Digest::SHA qw(sha1_hex);

$Carp::Verbose = 1;

our %multigraph_remove_space =
    ('ds-expr-' => 1,
     'graph-legend-' => 0);


# instance of Torrus::ServiceID object, if needed
my $srvIdParams;

# tree names where we initialized service IDs
my %srvIdInitialized;


sub new
{
    my $proto = shift;
    my %options = @_;
    my $class = ref($proto) || $proto;
    $options{'-WriteAccess'} = 1;
    my $self  = $class->SUPER::new( %options );
    if( not defined( $self ) )
    {
        return undef;
    }

    bless $self, $class;

    if( $self->{'store'}->created_init_commit() )
    {
        # The configtree branch is newly created. Cleanup Redis information.
        $self->_remove_githead();
    }

    if( $options{'-ForceRebuild'} or not defined($self->currentCommit()) )
    {
        $self->{'force_rebuild'} = 1;
    }

    # set up the srcfiles branch
    $self->{'srcstore'} =
        new Git::ObjectStore(
            'repodir' => $self->{'repodir'},
            'branchname' => $self->treeName() . '_srcfiles',
            'writer' => 1,
            %{$self->{'store_author'}});


    $self->{'viewparent'} = {};

    $self->{'collectorInstances'} =
        Torrus::SiteConfig::agentInstances( $self->treeName(), 'collector' );

    $self->{'is_writing'} = 1;

    $self->{'srcfiles_processing_now'} = {};
    $self->{'srcfiles_processed'} = {};
    $self->{'srcfiles_updated'} = {};

    $self->{'srcrefs'} = $self->_read_json('srcrefs');
    $self->{'srcrefs'} = {} unless defined $self->{'srcrefs'};

    $self->{'srcglobaldeps'} = $self->_read_json('srcglobaldeps');
    $self->{'srcglobaldeps'} = {} unless defined $self->{'srcglobaldeps'};

    $self->{'srcincludes'} = $self->_read_json('srcincludes');
    $self->{'srcincludes'} = {} unless defined $self->{'srcincludes'};

    return $self;
}


sub _agents_ref_name
{
    my $self = shift;
    return 'refs/heads/' . $self->treeName() . '_agents_ref';
}

sub _node_read
{
    my $self = shift;
    my $token = shift;

    my $ret;
    if( defined($self->{'editing_node'}) and $token eq $self->{'editing_node'} )
    {
        $ret = $self->{'editing'};
    }
    else
    {
        $ret = $self->SUPER::_node_read($token);
    }

    if( defined($ret) )
    {
        foreach my $name (keys %{$ret->{'vars'}})
        {
            $self->{'setvar'}{$token}{$name} = $ret->{'vars'}{$name};
        }
    }

    return $ret;
}


sub _agent_instance_name
{
    my $self = shift;
    my $agent = shift;
    my $instance = shift;

    return sprintf('%s_%.4x', $agent, $instance);
}


sub _agent_branch_name
{
    my $self = shift;
    my $agent = shift;
    my $instance = shift;

    return $self->{'treename'} . '_' .
        $self->_agent_instance_name($agent, $instance);
}


sub _write_json
{
    my $self = shift;
    my $filename = shift;
    my $data = shift;

    $self->{'store'}->write_file($filename, $self->{'json'}->encode($data));
    return;
}



sub startEditingOthers
{
    my $self  = shift;
    my $filename  = shift;

    $self->{'others_list_file'} = 'other/' . $filename;
    my $old_list = $self->_read_json($self->{'others_list_file'});
    $old_list = {} unless defined($old_list);
    $self->{'others_list'} = $old_list;
}


sub addOtherObject
{
    my $self  = shift;
    my $name  = shift;

    if( not defined($self->{'others_list_file'}) )
    {
        die('startEditingOthers() was not called');
    }

    $self->{'others_list'}{$name} = 1;
    $self->editOther($name);
    return;
}


sub endEditingOthers
{
    my $self  = shift;

    $self->_write_json($self->{'others_list_file'}, $self->{'others_list'});
    delete $self->{'others_list_file'};
    delete $self->{'others_list'};
    return;
}


sub editOther
{
    my $self  = shift;
    my $name  = shift;

    if( defined($self->{'editing'}) )
    {
        die('another object is being edited');
    }

    my $obj = $self->_other_read($name);
    if( not defined($obj) )
    {
        $obj = {'params' => {}};
    }

    $self->{'editing'} = $obj;
    $self->{'editing_name'} = $name;

    return;
}


sub setOtherParam
{
    my $self  = shift;
    my $param = shift;
    my $value = shift;

    if( $self->getParamProperty( $param, 'remspace' ) )
    {
        $value =~ s/\s+//sgo;
    }
    elsif( $self->getParamProperty( $param, 'squashspace' ) )
    {
        $value =~ s/\s+/ /sgo;
    }

    my $oldval = $self->{'editing'}{'params'}{$param};
    if( not defined($oldval) or $oldval ne $value )
    {
        $self->{'editing'}{'params'}{$param} = $value;
        $self->{'editing_dirty'} = 1;
    }

    return;
}

sub commitOther
{
    my $self  = shift;

    if( not defined($self->{'editing'}) )
    {
        die('setOtherParam() called before editOther()');
    }
    if( not defined($self->{'editing_name'}) )
    {
        die('a node object is being edited');
    }

    if( $self->{'editing_dirty'} )
    {
        $self->_write_json('other/' . $self->{'editing_name'},
                           $self->{'editing'});
    }

    delete $self->{'editing'};
    delete $self->{'editing_name'};
    delete $self->{'editing_dirty'};
}


# editNode can be called more than once on the same node, so we do
# nothing in this case.
# If it's called for a different node, we commit the previous one.

sub editNode
{
    my $self  = shift;
    my $path  = shift;

    my $token = $self->token($path, 1);

    if( defined($self->{'editing'}) )
    {
        if( $self->{'editing_node'} eq $token )
        {
            return $token;
        }
        else
        {
            $self->commitNode();
        }
    }

    my $node = $self->_node_read($token);
    if( not defined($node) )
    {
        my $is_subtree = ($path =~ /\/$/) ? 1:0;
        my $parent_token;

        if( $path eq '/' )
        {
            $parent_token = '';
        }
        else
        {
            my $slashpos =
                rindex($path, '/', length($path) - ($is_subtree?2:0));
            my $parent_path = substr($path, 0, $slashpos+1);
            $parent_token = $self->token($parent_path, 1);
            my $parent_node = $self->_node_read($parent_token);

            if( not defined($parent_node) or
                not $parent_node->{'children'}->{$token} )
            {
                # add a child token
                $self->editNode($parent_path);
                $self->{'editing'}{'children'}{$token} = 1;
                $self->{'editing_dirty_children'} = 1;
                $self->commitNode();
            }
        }

        $node = {
            'is_subtree' => $is_subtree,
            'parent' => $parent_token,
            'path' => $path,
            'params' => {},
            'vars' => {},
        };

        if( $is_subtree )
        {
            $node->{'children'} = {};
            $self->{'editing_dirty_children'} = 1;
        }

        $self->{'editing_dirty'} = 1;
        $self->{'objcache'}->set($token => $node);
    }
    else
    {
        $self->{'updating_node'} = 1;
    }

    $self->{'editing'} = $node;
    $self->{'editing_node'} = $token;

    return $token;
}



sub setNodeParam
{
    my $self  = shift;
    my $param = shift;
    my $value = shift;

    if( $self->getParamProperty( $param, 'remspace' ) )
    {
        $value =~ s/\s+//go;
    }
    elsif( $self->getParamProperty( $param, 'squashspace' ) )
    {
        $value =~ s/\s+/ /sgo;
    }

    my $oldval = $self->{'editing'}{'params'}{$param};
    if( not defined($oldval) or $oldval ne $value )
    {
        $self->{'editing'}{'params'}{$param} = $value;
        $self->{'editing_dirty'} = 1;
        $self->{'editing_dirty_params'} = 1;
    }

    return;
}




sub setVar
{
    my $self = shift;
    my $token = shift;
    my $name = shift;
    my $value = shift;

    $self->{'setvar'}{$token}{$name} = $value;

    my $oldval = $self->{'editing'}{'vars'}{$name};
    if( not defined($oldval) or $oldval ne $value )
    {
        $self->{'editing'}{'vars'}{$name} = $value;
        $self->{'editing_dirty'} = 1;
        $self->{'editing_dirty_params'} = 1;
    }

    return;
}


sub commitNode
{
    my $self  = shift;

    if( not defined($self->{'editing'}) )
    {
        die('setOtherParam() called before editOther()');
    }
    if( not defined($self->{'editing_node'}) )
    {
        die('an object being edited is not a node');
    }

    if( $self->{'editing_dirty'} or $self->{'editing_dirty_children'} )
    {
        my $sha_file = $self->_sha_file($self->{'editing_node'});

        if( $self->{'editing_dirty'} )
        {
            # flush cached values
            $self->{'editing'}{'xparams'} = {};
            $self->{'editing'}{'uparams'} = {};

            my $data = {
                'is_subtree' => $self->{'editing'}{'is_subtree'},
                'parent' => $self->{'editing'}{'parent'},
                'path' => $self->{'editing'}{'path'},
                'params' => $self->{'editing'}{'params'},
                'vars' => $self->{'editing'}{'vars'},
            };

            if( $self->{'editing_dirty_params'} )
            {
                # find the topmost ancestor that is affected by each source file

                if( defined($self->{'editing'}{'src'}) )
                {
                    $data->{'src'} = $self->{'editing'}{'src'};
                }

                foreach my $srcfile (keys %{$self->{'srcfiles_processing_now'}})
                {
                    my $src_found;

                    if( defined($data->{'src'}) and $data->{'src'}{$srcfile} )
                    {
                        $src_found = 1;
                    }

                    my $ancestor;
                    if( not $src_found )
                    {
                        $ancestor = $data->{'parent'};
                    }

                    while( not $src_found and $ancestor ne '' )
                    {
                        my $node = $self->_node_read($ancestor);

                        if( defined($node->{'src'}) and
                            $node->{'src'}{$srcfile} )
                        {
                            $src_found = 1;
                        }

                        $ancestor = $node->{'parent'};
                    }

                    if( not $src_found )
                    {
                        my $had_src_before = defined($data->{'src'});

                        $data->{'src'}{$srcfile} = 1;
                        $self->{'srcrefs'}{$srcfile}{
                            $self->{'editing_node'}} = 1;

                        if( not $had_src_before )
                        {
                            # this is for the object cache
                            $self->{'editing'}{'src'}{$srcfile} = 1;
                        }

                        if( $self->{'updating_node'} )
                        {
                            # this srcfile is updating a previously
                            # defined node. Now we find a nearest parent
                            # with source references and copy them here.

                            if( not $had_src_before )
                            {
                                $ancestor = $data->{'parent'};
                                my $found_ancestor_with_src;
                                while( not defined($found_ancestor_with_src)
                                       and $ancestor ne '' )
                                {
                                    my $node = $self->_node_read($ancestor);
                                    if( defined($node->{'src'}) )
                                    {
                                        $found_ancestor_with_src = $node;
                                    }
                                    $ancestor = $node->{'parent'};
                                }

                                if( defined($found_ancestor_with_src) )
                                {
                                    foreach my $ancsrc
                                        (keys %{$found_ancestor_with_src->
                                                {'src'}})
                                    {
                                        $data->{'src'}{$ancsrc} = 1;
                                        $self->{'srcrefs'}{$ancsrc}{
                                            $self->{'editing_node'}} = 1;
                                        $self->{'editing'}{'src'}{$ancsrc} = 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            $self->_write_json('nodes/' . $sha_file, $data);
        }

        if( $self->{'editing_dirty_children'} )
        {
            $self->_write_json('children/' . $sha_file,
                               $self->{'editing'}{'children'});
        }
    }

    delete $self->{'editing'};
    delete $self->{'editing_node'};
    delete $self->{'editing_dirty'};
    delete $self->{'editing_dirty_params'};
    delete $self->{'editing_dirty_children'};
    delete $self->{'updating_node'};
    return;
}




sub setParamProperty
{
    my $self = shift;
    my $param = shift;
    my $prop = shift;
    my $value = shift;

    $self->{'paramprop'}{$prop}{$param} = $value;
    return;
}



sub addView
{
    my $self = shift;
    my $vname = shift;
    my $parent = shift;

    if( defined( $parent ) )
    {
        $self->{'viewparent'}{$vname} = $parent;
    }

    $self->addOtherObject($vname);
    return;
}



sub addDefinition
{
    my $self = shift;
    my $name = shift;
    my $value = shift;

    $self->_write_json('definitions/' . $name, $value);
    return;
}




sub isTrueVar
{
    my $self = shift;
    my $token = shift;
    my $name = shift;

    my $ret = 0;

    while( $token ne '' and
           not defined($self->{'setvar'}{$token}{$name}) )
    {
        my $node = $self->_node_read($token);
        $token = $node->{'parent'};
    }

    if( $token ne '' )
    {
        my $value = $self->{'setvar'}{$token}{$name};
        if( defined($value) )
        {
            if( $value eq 'true' or
                $value =~ /^\d+$/o and $value )
            {
                $ret = 1;
            }
        }
    }

    return $ret;
}




sub commitConfig
{
    my $self = shift;

    $self->editNode('/');
    $self->setNodeParam('tree-name', $self->treeName());
    $self->commitNode();

    $self->_write_json('srcrefs', $self->{'srcrefs'});
    $self->_write_json('srcglobaldeps', $self->{'srcglobaldeps'});
    $self->_write_json('srcincludes', $self->{'srcincludes'});
    $self->_write_json('paramprops', $self->{'paramprop'});

    $self->{'n_postprocessed_nodes'} = 0;
    $self->{'postprocessed_tokens'} = {};

    $self->{'updated_tokens'} = {};
    foreach my $srcfile (@{$self->{'srcfiles_rebuild_list'}})
    {
        if( defined($self->{'srcrefs'}{$srcfile}) )
        {
            foreach my $token (keys %{$self->{'srcrefs'}{$srcfile}})
            {
                $self->{'updated_tokens'}{$token} = 1;
            }
        }
    }

    foreach my $token (keys %{$self->{'updated_tokens'}})
    {
        if( not $self->_post_process_nodes($token) )
        {
            return 0;
        }
    }

    Verbose('Finished post-processing of ' . $self->{'n_postprocessed_nodes'} .
            ' nodes');

    # Propagate view inherited parameters
    $self->{'viewParamsProcessed'} = {};
    foreach my $vname ( $self->getViewNames() )
    {
        $self->_propagate_view_params( $vname );
    }

    my $src_changed = $self->{'srcstore'}->create_commit_and_packfile();

    if( $src_changed )
    {
        my $src_commit_id = $self->{'srcstore'}->current_commit_id();
        Debug('Wrote ' . $src_commit_id . ' in ' .
              $self->treeName() . '_srcfiles');

        Debug("Something is changed in source files");

        $self->_write_json('srcrev', $self->{'srcstore'}->current_commit_id());

        $self->{'config_updated'} =
            $self->{'store'}->create_commit_and_packfile();
    }

    if( $self->{'config_updated'} or $self->{'force_rebuild'} )
    {
        $self->{'new_commit'} = $self->{'store'}->current_commit_id();
    }

    if( $self->{'config_updated'} )
    {
        Debug('Wrote ' . $self->{'new_commit'} . ' in ' . $self->{'branch'});
    }

    # release memory
    delete $self->{'srcstore'};

    # replace the writer store object with reader and release the index memory
    delete $self->{'store'};

    $self->{'store'} = new Git::ObjectStore(
        'repodir' => $self->{'repodir'},
        'branchname' => $self->{'branch'},
        %{$self->{'store_author'}});

    $self->{'is_writing'} = undef;

    if( $self->{'config_updated'} )
    {
        # clean up tokenset members if their nodes were removed
        foreach my $ts ( $self->getTsets() )
        {
            foreach my $member ( $self->tsetMembers($ts) )
            {
                if( not $self->tokenExists($member) )
                {
                    $self->tsetDelMember($ts, $member);
                }
            }
        }
    }

    return 1;
}



sub _post_process_nodes
{
    my $self = shift;
    my $token = shift;

    if( $self->{'postprocessed_tokens'}{$token} )
    {
        return 1;
    }

    $self->{'postprocessed_tokens'}{$token} = 1;
    $self->{'n_postprocessed_nodes'}++;

    my $ok = 1;

    my $path = $self->path($token);

    my $nodeid = $self->getNodeParam( $token, 'nodeid', 1 );
    if( defined( $nodeid ) )
    {
        # verify the uniqueness of nodeid

        my $nodeid_sha = sha1_hex($nodeid);
        my $sha_file = 'nodeid/' . $self->_sha_file($nodeid_sha);
        my $old_entry = $self->_read_json($sha_file);
        if( defined($old_entry) )
        {
            if( $old_entry->[1] ne $token )
            {
                Error('Non-unique nodeid ' . $nodeid .
                      ' in ' . $path .
                      ' and ' . $self->path($old_entry->[1]));
                $ok = 0;
            }
        }
        else
        {
            $self->_write_json($sha_file, [$nodeid, $token]);

            # write the nodeid prefix search index
            my $pos = 0;
            while( ($pos = index($nodeid, '//', $pos)) >= 0 )
            {
                my $prefix = substr($nodeid, 0, $pos);
                my $dir = $self->_nodeidpx_sha_dir($prefix);
                $self->{'store'}->write_file($dir . '/' . $nodeid_sha, '');
                $pos+=2;
            }
        }
    }

    if( $self->isLeaf($token) )
    {
        # Process static tokenset members

        my $tsets = $self->getNodeParam($token, 'tokenset-member');
        if( defined( $tsets ) )
        {
            foreach my $tset ( split(/,/o, $tsets) )
            {
                my $tsetName = 'S'.$tset;
                if( not $self->tsetExists($tsetName) )
                {
                    Error("Referenced undefined tokenset $tset in $path");
                    $ok = 0;
                }
                else
                {
                    $self->tsetAddMember( $tsetName, $token, 'static' );
                }
            }
        }

        my $dsType = $self->getNodeParam( $token, 'ds-type' );
        if( defined( $dsType ) )
        {
            if( $dsType eq 'rrd-multigraph' )
            {
                # Expand parameter substitutions in multigraph leaves

                $self->editNode($path);

                my @dsNames =
                    split(/,/o, $self->getNodeParam($token, 'ds-names') );

                foreach my $dname ( @dsNames )
                {
                    foreach my $param ( 'ds-expr-', 'graph-legend-' )
                    {
                        my $dsParam = $param . $dname;
                        my $value = $self->getNodeParam( $token, $dsParam );
                        if( defined( $value ) )
                        {
                            my $newValue = $value;
                            if( $multigraph_remove_space{$param} )
                            {
                                $newValue =~ s/\s+//go;
                            }
                            
                            if( $newValue ne $value )
                            {
                                $self->setNodeParam( $dsParam, $newValue );
                            }
                        }
                    }
                }

                $self->commitNode();
            }
            elsif( $dsType eq 'collector' and
                   $self->{'collectorInstances'} > 0 )
            {
                $self->editNode($path);

                # Split the collecting job between collector instances
                my $instance = 0;
                my $nInstances = $self->{'collectorInstances'};

                my $oldOffset =
                    $self->getNodeParam($token, 'collector-timeoffset');
                my $newOffset = $oldOffset;

                my $period =
                    $self->getNodeParam($token, 'collector-period');

                if( $nInstances > 1 )
                {
                    my $hashString =
                        $self->getNodeParam($token,
                                            'collector-instance-hashstring');
                    if( not defined( $hashString ) )
                    {
                        Error('collector-instance-hashstring is not defined ' .
                              'in ' . $self->path( $token ));
                        $hashString = '';
                    }

                    $instance =
                        unpack( 'N', md5( $hashString ) ) % $nInstances;
                }

                $self->setNodeParam( 'collector-instance', $instance );

                my $dispersed =
                    $self->getNodeParam($token,
                                        'collector-dispersed-timeoffset');
                if( defined( $dispersed ) and $dispersed eq 'yes' )
                {
                    # Process dispersed collector offsets

                    my %p;
                    foreach my $param ( 'collector-timeoffset-min',
                                        'collector-timeoffset-max',
                                        'collector-timeoffset-step',
                                        'collector-timeoffset-hashstring' )
                    {
                        my $val = $self->getNodeParam( $token, $param );
                        if( not defined( $val ) )
                        {
                            Error('Mandatory parameter ' . $param . ' is not '.
                                  ' defined in ' . $self->path( $token ));
                            $ok = 0;
                        }
                        else
                        {
                            $p{$param} = $val;
                        }
                    }

                    if( $ok )
                    {
                        my $min = $p{'collector-timeoffset-min'};
                        my $max = $p{'collector-timeoffset-max'};
                        if( $max < $min )
                        {
                            Error('collector-timeoffset-max is less than ' .
                                  'collector-timeoffset-min in ' .
                                  $self->path( $token ));
                            $ok = 0;
                        }
                        else
                        {
                            my $step = $p{'collector-timeoffset-step'};
                            my $hashString =
                                $p{'collector-timeoffset-hashstring'};

                            my $bucketSize = ceil(($max-$min)/$step);
                            $newOffset =
                                $min
                                +
                                $step * ( unpack('N', md5($hashString)) %
                                          $bucketSize )
                                +
                                $instance * ceil($step/$nInstances);
                        }
                    }
                }
                else
                {
                    $newOffset += $instance * ceil($period/$nInstances);
                }

                $newOffset %= $period;

                if( $newOffset != $oldOffset )
                {
                    $self->setNodeParam('collector-timeoffset', $newOffset );
                }

                my $storagetypes =
                    $self->getNodeParam( $token, 'storage-type' );
                foreach my $stype ( split(/,/o, $storagetypes) )
                {
                    if( $stype eq 'ext' )
                    {
                        if( not defined( $srvIdParams ) )
                        {
                            $srvIdParams =
                                new Torrus::ServiceID( -WriteAccess => 1 );
                        }

                        my $srvTrees =
                            $self->getNodeParam($token, 'ext-service-trees');

                        if( not defined( $srvTrees ) or
                            length( $srvTrees ) == 0 )
                        {
                            $srvTrees = $self->treeName();
                        }

                        my $serviceid =
                            $self->getNodeParam($token, 'ext-service-id');

                        foreach my $srvTree (split(/\s*,\s*/o, $srvTrees))
                        {
                            if( not Torrus::SiteConfig::treeExists($srvTree) )
                            {
                                Error
                                    ('Error processing ext-service-trees' .
                                     'for ' . $self->path( $token ) .
                                     ': tree ' . $srvTree .
                                     ' does not exist');
                                $ok = 0;
                            }
                            else
                            {
                                if( not $srvIdInitialized{$srvTree} )
                                {
                                    $srvIdParams->cleanAllForTree
                                        ( $srvTree );
                                    $srvIdInitialized{$srvTree} = 1;
                                }
                                else
                                {
                                    if( $srvIdParams->idExists( $serviceid,
                                                                $srvTree ) )
                                    {
                                        Error('Duplicate ServiceID: ' .
                                              $serviceid . ' in tree ' .
                                              $srvTree);
                                        $ok = 0;
                                    }
                                }
                            }
                        }

                        if( $ok )
                        {
                            # sorry for ackward Emacs auto-indent
                            my $params = {
                                'trees' => $srvTrees,
                                'token' => $token,
                                'dstype' =>
                                    $self->getNodeParam($token,
                                                        'ext-dstype'),
                                    'units' =>
                                    $self->getNodeParam
                                    ($token, 'ext-service-units')
                                };

                            $srvIdParams->add( $serviceid, $params );
                        }
                    }
                }

                $self->commitNode();
            }
        }
        else
        {
            Error("Mandatory parameter 'ds-type' is not defined for $path");
            $ok = 0;
        }
    }
    else
    {
        foreach my $ctoken ( $self->getChildren($token) )
        {
            $ok = $self->_post_process_nodes( $ctoken ) ? $ok:0;
        }
    }

    return $ok;
}


sub _propagate_view_params
{
    my $self = shift;
    my $vname = shift;

    # Avoid processing the same view twice
    if( $self->{'viewParamsProcessed'}{$vname} )
    {
        return;
    }

    # First we do the same for parent
    my $parent = $self->{'viewparent'}{$vname};
    if( defined( $parent ) )
    {
        $self->_propagate_view_params( $parent );

        $self->editOther($vname);

        my $parentParams = $self->getOtherParams($parent);
        foreach my $param ( keys %{$parentParams} )
        {
            if( not defined( $self->getOtherParam( $vname, $param ) ) )
            {
                $self->setOtherParam($param, $parentParams->{$param});
            }
        }

        $self->commitOther();
    }

    # mark this view as processed
    $self->{'viewParamsProcessed'}{$vname} = 1;
    return;
}


sub startSrcFileProcessing
{
    my $self = shift;
    my $filename = shift;
    $self->{'srcfiles_processing_now'}{$filename} = 1;
    return;
}

sub endSrcFileProcessing
{
    my $self = shift;
    my $filename = shift;
    delete $self->{'srcfiles_processing_now'}{$filename};
    return;
}


sub addSrcFile
{
    my $self = shift;
    my $filename = shift;
    my $blobref = shift;

    my $file_changed =
        $self->{'srcstore'}->write_and_check($filename, $blobref);
    if( $file_changed )
    {
        $self->{'srcfiles_updated'}{$filename} = 1;
    }

    if( not defined($self->{'srcincludes'}{$filename}) )
    {
        $self->{'srcincludes'}{$filename} = [];
    }

    $self->{'srcfiles_processed'}{$filename} = 1;

    return $file_changed;
}



sub setSrcGlobalDep
{
    my $self = shift;
    my $filename = shift;
    $self->{'srcglobaldeps'}{$filename} = 1;
    return;
}



sub readSrcFile
{
    my $self = shift;
    my $filename = shift;
    return $self->{'srcstore'}->read_file($filename);
}


sub clearSrcIncludes
{
    my $self = shift;
    my $filename = shift;
    $self->{'srcincludes'}{$filename} = [];
    return;
}


sub addSrcInclude
{
    my $self = shift;
    my $filename = shift;
    my $include = shift;

    push(@{$self->{'srcincludes'}{$filename}}, $include);
    return;
}


sub analyzeSrcUpdates
{
    my $self = shift;

    $self->{'srcfiles_rebuild'} = {};

    # Detect source files which were removed
    foreach my $filename (sort keys %{$self->{'srcincludes'}})
    {
        if( $filename ne '__ROOT__' and
            not $self->{'srcfiles_processed'}{$filename} )
        {
            Verbose("$filename was removed from source configuration");
            $self->_mark_related_srcfiles_dirty($filename);
            $self->_delete_dependent_nodes($filename);
            $self->{'srcstore'}->delete_file($filename);
            delete $self->{'srcincludes'}{$filename};
        }
    }

    # step 1: find additional files that need to be re-compiled
    $self->_analyze_updates('__ROOT__');
    
    # step 2: build an ordered list of files to recompile
    my $rebuild_list = [];
    push( @{$rebuild_list}, $self->_compose_rebuild_list('__ROOT__') );
    
    foreach my $filename (@{$rebuild_list})
    {
        $self->_delete_dependent_nodes($filename);
    }

    # _delete_dependent_nodes may mark additional files dirty, so
    # compose the list once again
    $rebuild_list = [];
    push( @{$rebuild_list}, $self->_compose_rebuild_list('__ROOT__') );
    
    $self->{'srcfiles_rebuild_list'} = $rebuild_list;
    return $rebuild_list;
}


sub _delete_dependent_nodes
{
    my $self = shift;
    my $filename = shift;

    return unless defined($self->{'srcrefs'}{$filename});
    Debug("Deleting dependencies of $filename");

    foreach my $token (sort keys %{$self->{'srcrefs'}{$filename}})
    {
        # we might have deleted this node already
        if( $self->tokenExists($token) )
        {
            Debug('Deleting recursively: ' . $self->path($token));
            $self->_delete_node($token);
        }
    }

    delete $self->{'srcrefs'}{$filename};
    return;
}


sub _analyze_updates
{
    my $self = shift;
    my $filename = shift;

    if( ($self->{'srcfiles_updated'}{$filename} or $self->{'force_rebuild'})
        and
        not $self->{'srcfiles_rebuild'}{$filename} )
    {
        $self->{'srcfiles_rebuild'}{$filename} = 1;
        $self->_mark_related_srcfiles_dirty($filename);

        if( $self->{'srcglobaldeps'}{$filename} )
        {
            Debug("A global dependency file updated: $filename");
            # this file contains global definitions and templates.
            # Mark dirty all the files which include this one

            foreach my $xfile (keys %{$self->{'srcincludes'}})
            {
                foreach my $yfile (@{$self->{'srcincludes'}{$xfile}})
                {
                    if( $yfile eq $filename )
                    {
                        $self->{'srcfiles_rebuild'}{$xfile} = 1;
                        Debug("$xfile is dependent on $filename");
                    }
                }
            }
        }
    }

    if( defined($self->{'srcincludes'}{$filename}) )
    {
        foreach my $incfile (@{$self->{'srcincludes'}{$filename}})
        {
            $self->_analyze_updates($incfile);
        }
    }

    return;
}


    



sub _mark_related_srcfiles_dirty
{
    my $self = shift;
    my $filename = shift;

    # find dependent tokens and mark their src files as dirty
    if( defined($self->{'srcrefs'}{$filename}) )
    {
        foreach my $token (keys %{$self->{'srcrefs'}{$filename}})
        {
            foreach my $srcfile ($self->getSrcFiles($token))
            {
                # only those that were pre-processed
                if( $self->{'srcfiles_processed'}{$srcfile} and
                    not $self->{'srcfiles_rebuild'}{$srcfile} )
                {
                    Debug('Marking file dirty: ' . $srcfile);
                    $self->{'srcfiles_rebuild'}{$srcfile} = 1;
                }
            }
        }
    }
    return;
}



sub _compose_rebuild_list
{
    my $self = shift;
    my $filename = shift;

    my @ret;
    
    if( defined($self->{'srcincludes'}{$filename}) )
    {
        foreach my $incfile (@{$self->{'srcincludes'}{$filename}})
        {
            push(@ret, $self->_compose_rebuild_list($incfile));
        }
    }

    if( $self->{'srcfiles_rebuild'}{$filename} )
    {
        # add all templates and definitions in the rebuild list
        my @includes = $self->_get_all_includes($filename);
        foreach my $incfile (@includes)
        {
            if( $self->{'srcglobaldeps'}{$incfile} )
            {
                push(@ret, $incfile);
            }
        }

        if( $filename ne '__ROOT__' )
        {
            push(@ret, $filename);
        }
    }
    
    return @ret;
}


sub _get_all_includes
{
    my $self = shift;
    my $filename = shift;

    my @ret;
    
    if( defined($self->{'srcincludes'}{$filename}) )
    {
        foreach my $incfile (@{$self->{'srcincludes'}{$filename}})
        {
            push(@ret, $self->_get_all_includes($incfile));
            push(@ret, $incfile);
        }
    }

    return @ret;
}



sub getSrcIncludes
{
    my $self = shift;
    my $filename = shift;
    if( defined($self->{'srcincludes'}{$filename}) )
    {
        return @{$self->{'srcincludes'}{$filename}};
    }
    else
    {
        return ();
    }
}




sub _delete_node
{
    my $self = shift;
    my $token = shift;

    my $node = $self->_node_read($token);

    my $nodeid = $self->getNodeParam( $token, 'nodeid', 1 );
    if( defined($nodeid) )
    {
        my $nodeid_sha = sha1_hex($nodeid);
        $self->{'store'}->delete_file(
            'nodeid/' . $self->_sha_file($nodeid_sha));

        my $pos = 0;
        while( ($pos = index($nodeid, '//', $pos)) >= 0 )
        {
            my $prefix = substr($nodeid, 0, $pos);
            my $dir = $self->_nodeidpx_sha_dir($prefix);
            $self->{'store'}->delete_file($dir . '/' . $nodeid_sha);
            $pos+=2;
        }
    }

    my $parent = $node->{'parent'};
    my $iamsubtree = $node->{'is_subtree'};

    if( $iamsubtree )
    {
        foreach my $ctoken ( $self->getChildren($token) )
        {
            $self->_delete_node($ctoken);
        }
    }

    if( defined($node->{'src'}) )
    {
        foreach my $srcfile (keys %{$node->{'src'}})
        {
            delete $self->{'srcrefs'}{$srcfile}{$token};
            if( not $self->{'srcfiles_rebuild'}{$srcfile} and
                $self->{'srcfiles_processed'}{$srcfile} )
            {
                Debug('Adding to srcfiles_rebuild: ' . $srcfile);
                $self->{'srcfiles_rebuild'}{$srcfile} = 1;
            }
        }
    }

    my $sha_file = $self->_sha_file($token);
    $self->{'store'}->delete_file('nodes/' . $sha_file);
    $self->{'objcache'}->remove($token);

    if( $iamsubtree )
    {
        $self->{'store'}->delete_file('children/' . $sha_file);
    }

    # remove ourselves from parent's list of children
    if( $parent ne '' )
    {
        $self->editNode($self->path($parent));
        delete $self->{'editing'}{'children'}{$token};
        $self->{'editing_dirty_children'} = 1;
        $self->commitNode();
    }

    return;
}


sub validate
{
    my $self = shift;

    my $prev_commit = $self->currentCommit();
    if( defined($prev_commit) and
        not $self->{'config_updated'} and
        not $self->{'force_rebuild'} )
    {
        Debug('Nothing is changed and configuration was validated ' .
              'previously. Skipping the validation');
        return 1;
    }

    my $ok = 1;

    $ok = Torrus::ConfigTree::Validator::validateNodes($self);

    $ok = Torrus::ConfigTree::Validator::validateViews($self) ? $ok:0;
    $ok = Torrus::ConfigTree::Validator::validateMonitors($self) ? $ok:0;
    $ok = Torrus::ConfigTree::Validator::validateTokensets($self) ? $ok:0;

    return $ok;
}


sub finalize
{
    my $self = shift;
    my $status = shift;

    if( $status )
    {
        if( $self->{'config_updated'} or $self->{'force_rebuild'} )
        {
            $self->{'redis'}->hset
                ($self->{'redis_prefix'} . 'githeads',
                 $self->{'branch'},
                 $self->{'new_commit'});
            
            $self->{'redis'}->publish
                ($self->{'redis_prefix'} . 'treecommits:' . $self->treeName(),
                 $self->{'new_commit'});
            
            Verbose('Configuration has compiled successfully');
        }
    }
    else
    {
        my $prev_commit = $self->currentCommit();
        if( defined($prev_commit) and $prev_commit eq $self->{'new_commit'} )
        {
            Error('This configuration was previously successfully validated, ' .
                  'but now it is invalid. As a result, there is no valid ' .
                  'configuration at all, and some processes may need a ' .
                  'restart.');
            $self->_remove_githead();
        }
    }
    return;
}


sub _remove_githead
{
    my $self = shift;
    $self->{'redis'}->hdel
        ($self->{'redis_prefix'} . 'githeads', $self->{'branch'});
    return;
}


sub updateAgentConfigs
{
    my $self = shift;

    my $stores = {};
    my @branchnames;

    for( my $inst = 0; $inst < $self->{'collectorInstances'}; $inst++ )
    {
        push(@branchnames, $self->_agent_branch_name('collector', $inst));
    }

    if( Torrus::SiteConfig::mayRunMonitor($self->treeName()) )
    {
        push(@branchnames, $self->_agent_branch_name('monitor', 0));
    }

    if( scalar(@branchnames) == 0 )
    {
        Debug('This tree does not run any agents');
        return;
    }
    
    # open ObjectStore writer objects for every agent branch

    foreach my $branchname (@branchnames)
    {
        $stores->{$branchname} =
            new Git::ObjectStore(
                'repodir' => $self->{'repodir'},
                'branchname' => $branchname,
                'writer' => 1,
                %{$self->{'store_author'}});
    }

    my $agent_tokens_branch = $self->treeName() . '_agent_tokens';
    $self->{'agent_tokens_store'} =
        new Git::ObjectStore(
            'repodir' => $self->{'repodir'},
            'branchname' => $agent_tokens_branch,
            'writer' => 1,
            %{$self->{'store_author'}});

    my $refname = $self->_agents_ref_name();
    my $ref = Git::Raw::Reference->lookup($refname, $self->{'store'}->repo());

    my $old_commit_id = '';
    if( defined($ref) and not $self->{'force_rebuild'} )
    {
        $old_commit_id = $ref->peel('commit')->id();
    }
    # Debug('Old commit in ' . $self->{'branch'} . ': ' . $old_commit_id);

    my $new_commit_id = $self->currentCommit();
    # Debug('New commit: ' . $new_commit_id);

    if( $new_commit_id eq $old_commit_id )
    {
        Verbose('Nothing is changed in configtree, skipping the agents update');
        # Make sure that Redis has up to date commit ID.
        foreach my $branchname (@branchnames)
        {
            $self->{'redis'}->hset
                ($self->{'redis_prefix'} . 'githeads',
                 $branchname,
                 $stores->{$branchname}->current_commit_id());
        }

        return 0;
    }

    $self->{'token_updated'} = {};

    my $n_updated = 0;
    my $n_deleted = 0;

    my $cb_updated = sub {
        $n_updated += $self->_write_agent_configs($stores, $_[0]);
    };

    my $cb_deleted = sub {
        my $sha_file = $self->_sha_file($_[0]);
        my $ab_content = $self->{'agent_tokens_store'}->read_file($sha_file);
        if( defined($ab_content) )
        {
            $n_deleted++;
            my $agent_branches = $self->{'json'}->decode($ab_content);
            foreach my $branchname (@{$agent_branches})
            {
                $stores->{$branchname}->delete_file($sha_file);
            }

            $self->{'agent_tokens_store'}->delete_file($sha_file);
        }
    };

    $self->getUpdates($old_commit_id, $cb_updated, $cb_deleted);
    Verbose("Updated: $n_updated, Deleted: $n_deleted leaf nodes");

    foreach my $branchname (@branchnames)
    {
        if( $stores->{$branchname}->create_commit_and_packfile() )
        {
            my $commit_id = $stores->{$branchname}->current_commit_id();
            Debug('Wrote ' . $commit_id . ' in ' . $branchname);
            $self->{'redis'}->hset
                ($self->{'redis_prefix'} . 'githeads',
                 $branchname,
                 $commit_id);
        }
        else
        {
            Debug('Nothing changed in ' . $branchname);
        }
    }

    if( $self->{'agent_tokens_store'}->create_commit_and_packfile() )
    {
        my $commit_id = $self->{'agent_tokens_store'}->current_commit_id();
        Debug('Wrote ' . $commit_id . ' in ' . $agent_tokens_branch);
    }
    else
    {
        Debug('Nothing changed in ' . $agent_tokens_branch);
    }

    my $repo = $self->{'store'}->repo();
    my $new_commit = Git::Raw::Commit->lookup($repo, $new_commit_id);
    Git::Raw::Reference->create(
        $self->_agents_ref_name(), $repo, $new_commit, 1);
    Debug('Updated reference: ' . $self->_agents_ref_name());

    return;
}





sub _write_agent_configs
{
    my $self = shift;
    my $stores = shift;
    my $token = shift;

    if( $self->{'token_updated'}{$token} )
    {
        return 0;
    }

    if( not $self->isLeaf($token) )
    {
        my $count = 0;
        foreach my $ctoken ( $self->getChildren($token) )
        {
            $count += $self->_write_agent_configs($stores, $ctoken);
        }

        $self->{'token_updated'}{$token} = 1;
        return $count;
    }

    my $sha_file = $self->_sha_file($token);
    my @branches;

    my $dsType = $self->getNodeParam($token, 'ds-type');
    if( $dsType eq 'collector' )
    {
        my $instance = $self->getNodeParam($token, 'collector-instance');

        my $params = {'path' => $self->path($token)};
        foreach my $param (
            'collector-timeoffset',
            'collector-period',
            'collector-type',
            'storage-type',
            'transform-value',
            'collector-scale',
            'value-map')
        {
            my $val = $self->getNodeParam($token, $param);
            if( defined($val) )
            {
                $params->{$param} = $val;
            }
        }

        $self->_fetch_collector_params($token, $params);

        my $branchname = $self->_agent_branch_name('collector', $instance);
        $stores->{$branchname}->write_file(
            $sha_file,  $self->{'json'}->encode($params));
        push( @branches, $branchname );
    }

    if( $dsType ne 'rrd-multigraph' and
        Torrus::SiteConfig::mayRunMonitor($self->treeName()) )
    {
        # monitor
        my $mlist = $self->getNodeParam($token, 'monitor');
        if( defined $mlist )
        {
            my $params = {'path' => $self->path($token),
                          'monitor' => $mlist};

            foreach my $param ('monitor-period',
                               'monitor-timeoffset')
            {
                $params->{$param} = $self->getNodeParam($token, $param);
            }

            my $branchname = $self->_agent_branch_name('monitor', 0);
            $stores->{$branchname}->write_file(
                $sha_file,  $self->{'json'}->encode($params));
            push( @branches, $branchname );
        }
    }

    $self->{'token_updated'}{$token} = 1;

    # compare the new list of branches with the old one, and delete from
    # old branches if needed

    my @old_branches;

    my $ab_content = $self->{'agent_tokens_store'}->read_file($sha_file);
    if( defined($ab_content) )
    {
        my $agent_branches = $self->{'json'}->decode($ab_content);
        @old_branches = @{$agent_branches};
    }

    foreach my $branchname (@old_branches)
    {
        if( not grep {$_ eq $branchname} @branches )
        {
            $stores->{$branchname}->delete_file($sha_file);
        }
    }

    if( scalar(@branches) > 0 )
    {
        $self->{'agent_tokens_store'}->write_file(
            $sha_file, $self->{'json'}->encode(\@branches));
        return 1;
    }
    else
    {
        if( defined($ab_content) )
        {
            $self->{'agent_tokens_store'}->delete_file($sha_file);
        }
        return 0;
    }
}



sub _fetch_collector_params
{
    my $self = shift;
    my $token = shift;
    my $params = shift;

    my $r = $self->getInstanceParamsByMap(
        $token, 'node', \%Torrus::ConfigTree::Validator::collector_params);
    if( not defined($r) )
    {
        die("Failure while retrieving agent configuration");
    }

    while(my($key, $value) = each %{$r})
    {
        $params->{$key} = $value;
    }
    
    return;
}




1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
