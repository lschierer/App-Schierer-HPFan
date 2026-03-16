package App::Schierer::HPFan::Role::CannonQuote;
# cspell: disable

use v5.42.0;
use utf8::all;
use Mooish::Base -role;

use Mojo::DOM58;

sub process_cannon_quotes ($self, $html) {
  my $dom = Mojo::DOM58->new($html);

  # Find every <cannon-quote> tag
  $dom->find('cannon-quote')->each(sub {
    my $opening_p = shift->parent;

    # 2. Find the "broken" closing tag.
    # Discount likely turned </cannon-quote> into text or a malformed node.
    # We look for the sibling <p> that contains the string "/cannon-quote"
    my $closing_p =
      $opening_p->following_nodes->grep(sub { $_->text =~ m|/cannon-quote| })
      ->first;

    if ($closing_p) {
      $self->logger->info('found closing_p for cannon-quote');
      # 3. Collect all nodes between the start and end
      # We wrap them in your desired div
      my $content = '';
      my $current = $opening_p->next;
      while ($current && $current->text !~ m|/cannon-quote|) {
        $content .= $current->to_string;
        my $to_remove = $current;
        $current = $current->next;
        $to_remove->remove;
      }

      # 4. Replace the opening and closing <p> artifacts
      $opening_p->replace(qq{<div class="cannon-quote">$content</div>});
      $closing_p->remove;
    }
    else {
      $self->logger->error('closing_p not found for cannon-quote');
    }
  });

  return $dom->to_string;
}

1;

__END__

=head1 NAME

App::Schierer::HPFan::Role::CannonQuote - Process cannon quote blocks

=head1 DESCRIPTION

This role provides a method to post-process HTML content, replacing
custom <cannon-quote> tags with styled divs for displaying canonical
source material quotes in fanfiction.

=head1 USAGE

In your markdown file:

  <cannon-quote>
  *Quoted text from the original work...*
  </cannon-quote>

=head1 METHODS

=head2 process_cannon_quotes($html)

Post-processes HTML content, replacing <cannon-quote> tags with
<div class="cannon-quote"> for styling.

=cut
