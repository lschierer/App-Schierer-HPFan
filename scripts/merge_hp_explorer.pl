#!/usr/bin/env perl
use v5.42.0;
use utf8::all;
use JSON::PP;
use Path::Tiny;
use Time::Piece;

# Usage: merge_hp_explorer.pl file1.json file2.json [output_dir]

die "Usage: $0 file1.json file2.json [output_dir]\n" unless @ARGV >= 2;

my $file1_path = shift @ARGV;
my $file2_path = shift @ARGV;
my $output_dir = shift @ARGV // '.';

# Validate input files exist
die "File not found: $file1_path\n" unless -f $file1_path;
die "File not found: $file2_path\n" unless -f $file2_path;

# Create output directory if it doesn't exist
path($output_dir)->mkpath unless -d $output_dir;

# Load JSON files
my $json = JSON::PP->new->pretty->canonical;
my $data1 = $json->decode(path($file1_path)->slurp_raw);
my $data2 = $json->decode(path($file2_path)->slurp_raw);

# Extract dates from filenames to determine which is newer
my ($date1) = $file1_path =~ /(\d{4}-\d{2}-\d{2})/;
my ($date2) = $file2_path =~ /(\d{4}-\d{2}-\d{2})/;

# Determine which file is newer (use its top-level keys)
my $newer_data = (!$date1 || !$date2 || $date2 ge $date1) ? $data2 : $data1;

# Merge library arrays
my %library_by_id;

# Process both libraries
for my $data ($data1, $data2) {
    next unless $data->{library};

    for my $item (@{ $data->{library} }) {
        my $id = $item->{id};
        next unless $id;

        if (exists $library_by_id{$id}) {
            # Duplicate found - apply merge logic
            my $existing = $library_by_id{$id};
            my $winner = choose_better_item($existing, $item);
            $library_by_id{$id} = $winner;
        } else {
            # New item
            $library_by_id{$id} = $item;
        }
    }
}

# Choose which item to keep when there's a duplicate
sub choose_better_item {
    my ($item1, $item2) = @_;

    # Check if items have non-google links
    my $has_real_links1 = has_non_google_links($item1);
    my $has_real_links2 = has_non_google_links($item2);

    # If only one has real links, pick that one
    if ($has_real_links1 && !$has_real_links2) {
        return $item1;
    }
    if ($has_real_links2 && !$has_real_links1) {
        return $item2;
    }

    # Otherwise, pick the one with higher match_score
    my $score1 = $item1->{match_score} // 0;
    my $score2 = $item2->{match_score} // 0;

    return $score2 >= $score1 ? $item2 : $item1;
}

# Check if an item has links that are not google searches
sub has_non_google_links {
    my ($item) = @_;
    return 0 unless $item->{links};
    return 0 unless ref($item->{links}) eq 'HASH';

    for my $key (keys %{ $item->{links} }) {
        return 1 if $key ne 'google';
    }

    return 0;
}

# Build merged data structure
my $merged = {
    %$newer_data,  # Use all top-level keys from newer file
    library => [sort {
      $a->{title} cmp $b->{title} ||
        $a->{author} cmp $b->{author} ||
        ($b->{match_score} // 0) <=> ($a->{match_score} // 0)
    } values %library_by_id],  # Replace with merged library
};


# Generate output filename with today's date
my $today = Time::Piece->new->strftime('%Y-%m-%d');
my $output_file = path($output_dir)->child("hp_explorer_backup_$today.json");

# Write merged output
$output_file->spew_raw($json->encode($merged));

say "Merged library with " . scalar(keys %library_by_id) . " unique items";
say "Output written to: $output_file";

__END__

=head1 NAME

merge_hp_explorer.pl - Merge HP fanfic explorer backup JSON files

=head1 SYNOPSIS

    merge_hp_explorer.pl file1.json file2.json [output_dir]

=head1 DESCRIPTION

Merges two HP Explorer backup JSON files, deduplicating library entries by ID.

When duplicate IDs are found:
- If only one has non-google links, that one is kept
- Otherwise, the one with the higher match_score is kept

Top-level keys are taken from the file with the newer date in its filename.

Output file is named with today's date and written to current directory or
optional output_dir.

=cut
