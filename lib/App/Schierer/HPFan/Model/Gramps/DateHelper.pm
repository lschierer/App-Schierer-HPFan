use v5.42;
use utf8::all;
use experimental qw(class);

class App::Schierer::HPFan::Model::Gramps::DateHelper :
  isa(App::Schierer::HPFan::Logger) {
  use Carp;
  use Date::Manip;

  # Static methods for parsing and formatting Gramps dates

  method import_gramps_date ($parent_node, $xc) {
    # Check for each date type
    if (my $dateval = $xc->findnodes('g:dateval', $parent_node)->get_node(1)) {
      return {
        type      => 'dateval',
        val       => $dateval->getAttribute('val'),
        modifier  => $dateval->getAttribute('type') || '',  # before/after/about
        quality   => $dateval->getAttribute('quality')   || '',
        cformat   => $dateval->getAttribute('cformat')   || '',
        dualdated => $dateval->getAttribute('dualdated') || 0,
        newyear   => $dateval->getAttribute('newyear')   || '',
      };
    }
    elsif (my $daterange =
      $xc->findnodes('g:daterange', $parent_node)->get_node(1)) {
      return {
        type    => 'daterange',
        start   => $daterange->getAttribute('start'),
        stop    => $daterange->getAttribute('stop'),
        quality => $daterange->getAttribute('quality') || '',
        # ... other attributes
      };
    }
    elsif (my $datespan =
      $xc->findnodes('g:datespan', $parent_node)->get_node(1)) {
      return {
        type    => 'datespan',
        start   => $datespan->getAttribute('start'),
        stop    => $datespan->getAttribute('stop'),
        quality => $datespan->getAttribute('quality') || '',
        # ... other attributes
      };
    }
    elsif (my $datestr = $xc->findnodes('g:datestr', $parent_node)->get_node(1))
    {
      return {
        type => 'datestr',
        val  => $datestr->getAttribute('val'),
      };
    }

    return undef;    # No date found
  }

  method parse_gramps_date($date_element) {
    return undef unless $date_element;

    my $type = ref($date_element);

    if ($type eq 'HASH') {
      # Handle different date types based on keys
      if (exists $date_element->{val}) {
        return $self->_parse_dateval($date_element);
      }
      elsif (exists $date_element->{start} && exists $date_element->{stop}) {
        if (exists $date_element->{_type}
          && $date_element->{_type} eq 'datespan') {
          return $self->_parse_datespan($date_element);
        }
        else {
          return $self->_parse_daterange($date_element);
        }
      }
    }

    # Fallback for string dates
    return $self->_parse_datestr($date_element);
  }

  method format_date($date_data) {
    return undef unless $date_data;

    if (ref($date_data) eq 'HASH') {
      if (exists $date_data->{val}) {
        return $self->_format_dateval($date_data);
      }
      elsif (exists $date_data->{start} && exists $date_data->{stop}) {
        if (exists $date_data->{_type} && $date_data->{_type} eq 'datespan') {
          return $self->_format_datespan($date_data);
        }
        else {
          return $self->_format_daterange($date_data);
        }
      }
    }

    return "$date_data";    # String fallback
  }

  method _parse_dateval($dateval) {
    my $val     = $dateval->{val};
    my $type    = $dateval->{type}    || '';    # before, after, about
    my $quality = $dateval->{quality} || '';    # estimated, calculated

    my $date = ParseDate($val);
    return undef unless $date;

    return {
      date     => $date,
      type     => 'single',
      modifier => $type,
      quality  => $quality,
      original => $dateval
    };
  }

  method _parse_daterange($daterange) {
    my $start = ParseDate($daterange->{start});
    my $stop  = ParseDate($daterange->{stop});

    return {
      start_date => $start,
      end_date   => $stop,
      type       => 'range',
      quality    => $daterange->{quality} || '',
      original   => $daterange
    };
  }

  method _parse_datespan($datespan) {
    my $start = ParseDate($datespan->{start});
    my $stop  = ParseDate($datespan->{stop});

    return {
      start_date => $start,
      end_date   => $stop,
      type       => 'span',
      quality    => $datespan->{quality} || '',
      original   => $datespan
    };
  }

  method _parse_datestr($datestr) {
    my $val = ref($datestr) eq 'HASH' ? $datestr->{val} : $datestr;

    return {
      date_string => $val,
      type        => 'string',
      original    => $datestr
    };
  }

  method _format_dateval($dateval) {
    my $val     = $dateval->{val};
    my $type    = $dateval->{type}    || '';
    my $quality = $dateval->{quality} || '';

    my @parts;
    push @parts, "about"  if $type eq 'about';
    push @parts, "before" if $type eq 'before';
    push @parts, "after"  if $type eq 'after';
    push @parts, $val;
    push @parts, "($quality)" if $quality;

    return join(" ", @parts);
  }

  method _format_daterange($daterange) {
    my $start   = $daterange->{start};
    my $stop    = $daterange->{stop};
    my $quality = $daterange->{quality} || '';

    my $result = "between $start and $stop";
    $result .= " ($quality)" if $quality;

    return $result;
  }

  method _format_datespan($datespan) {
    my $start   = $datespan->{start};
    my $stop    = $datespan->{stop};
    my $quality = $datespan->{quality} || '';

    my $result = "from $start to $stop";
    $result .= " ($quality)" if $quality;

    return $result;
  }
}

1;
