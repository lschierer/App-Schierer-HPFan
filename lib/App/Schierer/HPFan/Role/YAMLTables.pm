package App::Schierer::HPFan::Role::YAMLTables;
# cspell: disable

use v5.42.0;
use utf8::all;
use Mooish::Base -role;
use Future::AsyncAwait;

use Mojo::DOM58;
use HTML::Escape qw(escape_html);

use Path::Tiny;
use YAML::XS qw(LoadFile);

async sub render_yaml_tables ($self, $html, $entry) {
  my $dom        = Mojo::DOM58->new($html);
  my $entry_path = Path::Tiny::path($entry->{path});
  my $entry_dir  = $entry_path->parent;

  # Find every <yamltable source="...">
  for my $node ($dom->find('yamltable[source]')->each) {
    my $source = $node->attr('source') // '';

    # Resolve relative path
    my $yaml_path = $entry_dir->child($source);

    unless ($yaml_path->exists) {
      $self->logger->warn("YAML file not found: $yaml_path");
      $node->replace(qq{<div class="error">YAML file not found: $source</div>});
      next;
    }

    # Load YAML data
    my $data;
    eval { $data = LoadFile($yaml_path->stringify); };
    if ($@) {
      $self->logger->error("Failed to load YAML from $yaml_path: $@");
      $node->replace(qq{<div class="error">Failed to load YAML: $@</div>});
      next;
    }

    # Build table from YAML data
    my $table_html = $self->_build_table_from_yaml($data);
    $node->replace($table_html);
  }

  return $dom->to_string;
}

sub _build_table_from_yaml ($self, $data) {
  # Check if data has metadata section
  my $column_order;
  my $rows;

  if ( ref($data) eq 'HASH'
    && exists $data->{columnorder}
    && exists $data->{rows}) {
    # New format with metadata
    $column_order = $data->{columnorder};
    $rows         = $data->{rows};
  }
  elsif (ref($data) eq 'ARRAY') {
    # Legacy format - just an array
    $rows = $data;
  }
  else {
    return
'<div class="error">YAML must be an array of objects or a hash with "rows" key</div>';
  }

  unless (ref($rows) eq 'ARRAY' && @$rows) {
    return '<div class="error">YAML rows must be a non-empty array</div>';
  }

  # Get column headers from first row keys
  my $first_row = $rows->[0];
  unless (ref($first_row) eq 'HASH') {
    return '<div class="error">YAML array must contain hash objects</div>';
  }

  # Determine column order
  my @columns;
  if ($column_order && ref($column_order) eq 'HASH') {
    # Sort by the rank values
    @columns =
      sort { $column_order->{$a} <=> $column_order->{$b} } keys %$column_order;
  }
  else {
    # Fall back to sorted keys
    @columns = sort keys %$first_row;
  }

  # Build table header
  my $thead_cells = join '',
    map {qq{<th class="spectrum-Table-headCell">$_</th>}} @columns;
  my $thead =
    qq{<thead class="spectrum-Table-head"><tr>$thead_cells</tr></thead>};

  # Build table rows
  my @row_html;
  for my $row (@$rows) {
    my @cells = map {
      my $value = $row->{$_} // '';
      # Convert markdown in cell values to HTML
      my $html_value = $self->markdown_string_to_html($value);
      qq{<td class="spectrum-Table-cell">$html_value</td>}
    } @columns;

    push @row_html,
        qq{<tr class="spectrum-Table-row spectrum-Table-cell--divider">}
      . join('', @cells)
      . qq{</tr>};
  }

  my $tbody =
      qq{<tbody class="spectrum-Table-body">}
    . join('', @row_html)
    . qq{</tbody>};

  return qq{
    <table class="spectrum-Table spectrum-Table--sizeM spectrum-Table--emphasized">
      $thead
      $tbody
    </table>
  };
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Module::YAMLTables - Thunderhorse module for rendering tables from YAML files

=head1 DESCRIPTION

This module provides a helper method to post-process HTML content, replacing
custom <yamltable source="..."> tags with rendered HTML tables built from
YAML data files.

=head1 USAGE

In your markdown file:

  <yamltable source="./data.yaml"></yamltable>

The YAML file should contain an array of objects:

  - Column1: value1
    Column2: value2
  - Column1: value3
    Column2: value4

=head1 REGISTERED METHODS

=head2 render_yaml_tables($html, $entry)

Post-processes HTML content, replacing <yamltable source="..."> tags with
tables built from the referenced YAML files. Paths are resolved relative
to the markdown file being rendered.

=cut
