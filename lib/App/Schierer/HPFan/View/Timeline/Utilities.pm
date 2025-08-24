use v5.42;
use utf8::all;
use experimental qw(class);
#require App::Schierer::HPFan::Model::History::Event;
require Scalar::Util;
require HTML::Strip;
require App::Schierer::HPFan::Model::History::Event;

package App::Schierer::HPFan::View::Timeline::Utilities {
  use List::AllUtils qw( any min max firstidx pairwise);
  use Scalar::Util   qw(blessed);
  #something about this package requies that it be used not just required
  use SVG;
  use Readonly;
  use Math::Trig ':pi';
  use POSIX    qw(ceil);
  use Exporter qw(import);
  use Carp;

  our @EXPORT      = qw( get_category_for_event );
  our %EXPORT_TAGS = (all_funcs => [qw( get_category_for_event )]);

  sub get_category_for_event($self, $event, $logger) {

    unless ($event->isa('App::Schierer::HPFan::Model::History::Event')) {
      $logger->logcroak(sprintf(
        'event must be %s not %s',
        'App::Schierer::HPFan::Model::History::Event',
        ref($event)
      ));
    }

    my $category = $event->event_class // 'generic';
    my @parts    = grep {length} split /\s+/, ($event->event_class // '');
    if (scalar @parts) {
      @parts = grep { $_ !~ /mundane/i } @parts;
      if (scalar @parts) {
        @parts    = sort @parts;
        $category = 'generic';
        if ($parts[0] =~ /england/i) {
          if ($#parts >= 1 && $parts[1] =~ /scotland/i) {
            $category = 'gb';
          }
        }
        if ($category eq 'generic' && scalar(@parts)) {
          $category = join(' ', @parts);
        }
      }
    }
    return $category;
  }

}
1;
__END__
