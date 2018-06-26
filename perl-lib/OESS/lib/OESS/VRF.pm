#!/usr/bin/perl

use strict;
use warnings;

package OESS::VRF;

use Log::Log4perl;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

use Data::Dumper;
use OESS::DB;
use OESS::Endpoint;
use OESS::Workgroup;
use NetAddr::IP;


=head1 NAME

OESS::VRF - VRF Interaction Module

=head1 SYNOPSIS

This is a module to provide a simplified object oriented way to connect to
and interact with the OESS VRFs.

Some examples:

    use OESS::VRF;

    my $vrf = OESS::VRF->new( vrf_id => 100, db => new OESS::Database());

    my $vrf_id = $vrf->get_id();

    if (! defined $vrf_id){
        warn "Uh oh, something bad happened: " . $vrf->get_error();
        exit(1);
    }

=cut





=head2 new

    Creates a new OESS::VRF object
    requires an OESS::Database handle
    and either the details from get_vrf_details or a vrf_id

=cut

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.VRF");
    
    my %args = (
	details => undef,
	vrf_id => undef,
	db => undef,
	just_display => 0,
        link_status => undef,
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
	$self->{'logger'}->error("No Database Object specified");
	return;
    }

    if(!defined($self->{'vrf_id'}) || $self->{'vrf_id'} == -1){
        #build from model
        $self->_build_from_model();
    }else{
        $self->_fetch_from_db();
    }

    return $self;
}

sub _build_from_model{
    my $self = shift;

    warn Dumper($self->{'model'});

    $self->{'name'} = $self->{'model'}->{'name'};
    $self->{'description'} = $self->{'model'}->{'description'};
    $self->{'prefix_limit'} = $self->{'model'}->{'prefix_limit'};

    $self->{'endpoints'} = ();
    #process Endpoints
    foreach my $ep (@{$self->{'model'}->{'endpoints'}}){
        push(@{$self->{'endpoints'}},OESS::Endpoint->new( db => $self->{'db'}, model => $ep, type => 'vrf'));
    }
    
    #process Workgroups
    $self->{'workgroup'} = OESS::Workgroup->new( db => $self->{'db'}, workgroup_id => $self->{'model'}->{'workgroup_id'});

    #process user
    $self->{'created_by'} = OESS::User->new( db => $self->{'db'}, user_id => $self->{'model'}->{'created_by'});
    $self->{'last_modified_by'} = OESS::User->new(db => $self->{'db'}, user_id => $self->{'model'}->{'last_modified_by'});
    $self->{'local_asn'} = $self->{'model'}->{'local_asn'} || 55038;

    return;
}

sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'endpoints'} = $hash->{'endpoints'};
    $self->{'name'} = $hash->{'name'};
    $self->{'description'} = $hash->{'description'};
    $self->{'prefix_limit'} = $hash->{'prefix_limit'};
    $self->{'workgroup'} = $hash->{'workgroup'};
    $self->{'created_by'} = $hash->{'created_by'};
    $self->{'last_modified_by'} = $hash->{'last_modified_by'};
    $self->{'created'} = $hash->{'created'};
    $self->{'last_modified'} = $hash->{'last_modified'};
    $self->{'local_asn'} = $hash->{'local_asn'};
}

sub _fetch_from_db{
    my $self = shift;

    my $hash = OESS::DB::VRF::fetch(db => $self->{'db'}, vrf_id => $self->{'vrf_id'});
    $self->from_hash($hash);

}

sub to_hash{
    my $self = shift;

    my $obj;

    $obj->{'name'} = $self->name();
    $obj->{'vrf_id'} = $self->vrf_id();
    $obj->{'description'} = $self->description();
    my @endpoints;
    foreach my $endpoint (@{$self->endpoints()}){
        push(@endpoints, $endpoint->to_hash());
    }

    $obj->{'endpoints'} = \@endpoints;
    $obj->{'prefix_limit'} = $self->prefix_limit();
    $obj->{'workgroup'} = $self->workgroup()->to_hash();
    $obj->{'created_by'} = $self->created_by()->to_hash();
    $obj->{'last_modified_by'} = $self->last_modified_by()->to_hash();
    $obj->{'created'} = $self->created();
    $obj->{'last_modified'} = $self->last_modified();
    $obj->{'local_asn'} = $self->local_asn();

    return $obj;
}

sub vrf_id{
    my $self =shift;
    return $self->{'vrf_id'};
}

sub id{
    my $self = shift;
    my $id = shift;

    if(!defined($id)){
        return $self->{'vrf_id'};
    }else{
        $self->{'vrf_id'} = $id;
        return $self->{'vrf_id'};
    }
}

sub endpoints{
    my $self = shift;
    my $eps = shift;

    if(!defined($eps)){
        if(!defined($self->{'endpoints'})){
            return []
        }
        return $self->{'endpoints'};
    }else{
        return [];
    }
}

sub name{
    my $self = shift;
    my $name = shift;
    
    if(!defined($name)){
        return $self->{'name'};
    }else{
        $self->{'name'} = $name;
        return $self->{'name'};
    }
}

sub description{
    my $self = shift;
    my $description = shift;

    if(!defined($description)){
        return $self->{'description'};
    }else{
        $self->{'description'} = $description;
        return $self->{'description'};
    }
}

sub workgroup{
    my $self = shift;
    my $workgroup = shift;

    if(!defined($workgroup)){

        return $self->{'workgroup'};
    }else{
        $self->{'workgroup'} = $workgroup;
        return $self->{'workgroup'};
    }
}

sub update_db{
    my $self = shift;

    if(!defined($self->{'vrf_id'})){
        $self->create();
    }else{
        $self->_edit();
    }
}

sub create{
    my $self = shift;
    
    #need to validate endpoints
    foreach my $ep (@{$self->endpoints()}){
        if( !$ep->interface()->vlan_valid( workgroup_id => $self->workgroup()->workgroup_id(), vlan => $ep->tag() )){
            $self->{'logger'}->error("VLAN: " . $ep->tag() . " is not allowed for workgroup on interface: " . $ep->interface()->name());
            return 0;
        }

        #validate IP addresses for peerings
        foreach my $peer (@{$ep->peers()}){
            my $peer_ip = NetAddr::IP->new($peer->peer_ip());
            my $local_ip = NetAddr::IP->new($peer->local_ip());
            if(!$local_ip->contains($peer_ip)){
                $self->{'logger'}->error("Peer and Local IPs are not in the same subnet...");
                return 0;
            }
        }
    }

    #validate that we have at least 2 endpoints
    if(scalar($self->endpoints()) < 2){
        $self->{'logger'}->error("VRF Needs at least 2 endpoints");
        return 0;
    }

    my $vrf_id = OESS::DB::VRF::create(db => $self->{'db'}, model => $self->to_hash());
    $self->{'vrf_id'} = $vrf_id;
    return 1;
}

sub _edit{
    my $self = shift;
    
    

}



=head2 update_vrf_details

    reload the vrf details from the database to make sure everything 
    is in sync with what should be there

=cut

sub update_vrf_details{
    my $self = shift;
    my %params = @_;

    $self->_fetch_from_db();
}

=head2 decom

=cut

sub decom{
    my $self = shift;
    my %params = @_;
    my $user_id = $params{'user_id'};
    
    foreach my $ep (@{$self->endpoints()}){
        $ep->decom();
    }

    my $res = OESS::DB::VRF::decom(db => $self->{'db'}, vrf_id => $self->{'vrf_id'}, user_id => $user_id);
    return $res;

}

=head2 error

=cut

sub error{
    my $self = shift;
    my $error = shift;
    if(defined($error)){
        $self->{'error'} = $error;
    }
    return $self->{'error'};
}

sub prefix_limit{
    my $self = shift;
    if(!defined($self->{'prefix_limit'})){
        return 1000;
    }
    return $self->{'prefix_limit'};
}

sub created_by{
    my $self = shift;
    my $created_by = shift;

    return $self->{'created_by'};
}

sub last_modified_by{
    my $self = shift;
    return $self->{'last_modified_by'};
}


sub last_modified{
    my $self = shift;
    return $self->{'last_modified'};
}

sub created{
    my $self = shift;
    return $self->{'created'};
}

sub local_asn{
    my $self = shift;
    return $self->{'local_asn'};
}

sub state{
    my $self = shift;
    return 'active';
}

1;