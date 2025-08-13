use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::Citation::Reference;
require App::Schierer::HPFan::Model::Gramps::Note::Reference;

class App::Schierer::HPFan::Model::Gramps::Reference :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Readonly;
  use overload
    '<=>' => \&_comparison,
    '=='  => \&_equality,
    '!='  => \&_inequality,
    '""'  => \&as_string;

  field $hlink : param : reader = undef;

  # there are a number of optional fields that are common to some,
  # but not all, reference types. Many of these are *almost* ubiquitous
  # and even more are totally unique to references.
  # I am representing these by adding the
  # *_attribute_optional for a subclass to indicate this *may* be present and
  # *_attribute_required for a subclass to indicate this *must* be present
  # these two fields are only used internally, but need to be *settable* by
  # child classes.

  field $region_attribute_optional : writer = 0;
  field $region_attribute_required : writer = 0;
  field $region;
  ADJUST {
    Readonly::Hash1 my %temp => (
      corner1_x => '',
      corner1_y => '',
      corner2_x => '',
      corner2_y => '',
    );
    $region = \%temp;
  }

  field $attribute_attribute_optional : writer = 0;
  field $attribute_attribute_required : writer = 0;
  field $attribute = [];

  field $citationref_attribute_optional : writer = 0;
  field $citationref_attribute_required : writer = 0;
  field $citationref = [];

  field $noteref_attribute_optional : writer = 0;
  field $noteref_attribute_required : writer = 0;
  field $noteref = [];

  field $XPathContext : param : reader //= undef;
  field $XPathObject  : param : reader //= undef;

  ADJUST {
    if (
      not(defined($hlink) or (defined($XPathContext) and defined($XPathObject)))
    ) {
      $self->logger->logcroak(
        'Either hlink, or both XPathContext and XPathObject must be provided.');
    }
    elsif (not defined($hlink)) {
      $self->_import();
    }
    elsif (defined($XPathObject) and defined($XPathContext)) {
      $self->debug('XPathObject is ' . ref $XPathObject);
    }
    elsif (defined $hlink) {
      $self->debug("hlink is $hlink");
    }
    elsif (defined($XPathContext)) {
      $self->logger->logcroak('XPathObject must be defined!!');
    }
    elsif (defined($XPathObject)) {
      $self->logger->logcroak('XPathContext must be defined!!');
    }
    else {
      $self->warn('something wierd initializing ' . __CLASS__);
    }
  }

  method _import {
    if (!$XPathObject) {
      return;
    }
    $hlink = $XPathObject->getAttribute('hlink');
    $self->logger->logcroak("hlink not discoverable in $XPathObject")
      unless defined $hlink;

    if ($region_attribute_required or $region_attribute_optional) {
      foreach my $attr (qw(corner1_x corner1_y corner2_x corner2_y)) {
        $region->{$attr} = $XPathContext->findnodes('./g:region', $XPathObject)
          ->getAttribute($attr);
        if ($region_attribute_required) {
          $self->logger->logcroak(
            "region/$attr not discoverable in $XPathObject")
            unless defined $region->{$attr};
        }
      }
    }

    if ($attribute_attribute_optional or $attribute_attribute_required) {
      foreach
        my $xAttr ($XPathContext->findnodes('./g:attribute', $XPathObject)) {
        my $attr_priv = $xAttr->getAttribute('priv');
        my $attr_type = $xAttr->getAttribute('type');
        my $attr_value => $xAttr->getAttribute('value');
        my $attr_citationref = [];
        my $attr_noteref     = [];

        foreach my $xanr ($XPathContext->findnodes('./g:citationref', $xAttr)) {
          push @$attr_citationref,
            App::Schierer::HPFan::Model::Gramps::Citation::Reference->new(
            XPathContext => $XPathContext,
            XPathObject  => $xanr,
            );
        }

        foreach my $xanr ($XPathContext->findnodes('./g:noteref', $xAttr)) {
          push @$attr_noteref,
            App::Schierer::HPFan::Model::Gramps::Note::Reference->new(
            XPathContext => $XPathContext,
            XPathObject  => $xanr,
            );
        }
        if (defined($attr_type)) {
          push @$attribute,
            {
            priv        => $attr_priv,
            type        => $attr_type,
            value       => $attr_value,
            citationref => $attr_citationref,
            noteref     => $attr_noteref,
            };
        }

      }
      if ($attribute_attribute_required and scalar @$attribute < 1) {
        $self->logger->logcroak('attribute is required for this reference.');
      }
    }

    if ($citationref_attribute_optional or $citationref_attribute_required) {
      foreach
        my $xRef (XPathContext->findnodes('./g:citationref', $XPathObject)) {
        push @$citationref,
          App::Schierer::HPFan::Model::Gramps::Reference->new(
          XPathContext => $XPathContext,
          XPathObject  => $xRef,
          );
      }
      if ($citationref_attribute_required and scalar(@$citationref) < 1) {
        $self->logger->logcroak('citationref is required for this reference.');
      }
    }

    if ($noteref_attribute_optional or $noteref_attribute_required) {
      foreach my $xRef (XPathContext->findnodes('./g:noteref', $XPathObject)) {
        push @$noteref,
          App::Schierer::HPFan::Model::Gramps::Reference->new(
          XPathContext => $XPathContext,
          XPathObject  => $xRef,
          );
      }
      if ($noteref_attribute_required and scalar(@$noteref) < 1) {
        $self->logger->logcroak('noteref is required for this reference.');
      }
    }

  }

  method _equality ($other, $swap = 0) {
    return $hlink eq $other->hlink;
  }

  method _inequality ($other, $swap = 0) {
    return $hlink ne $other->hlink;
  }

  method _comparison ($other, $swap = 0) {
    return $hlink cmp $other->hlink;
  }

  method to_hash {
    return { hlink => $hlink, };
  }

  method as_string {
    my $json =
      JSON::PP->new->utf8->pretty->canonical(1)
      ->allow_blessed(1)
      ->convert_blessed(1)
      ->encode($self->to_hash());
    return $json;
  }
}
1;
__END__
