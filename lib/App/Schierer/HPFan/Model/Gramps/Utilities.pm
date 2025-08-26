use v5.42;
use utf8::all;

package App::Schierer::HPFan::Model::Gramps::Utilities {
  use Carp ();
  use Readonly;
  use Scalar::Util   qw(blessed looks_like_number);
  use List::AllUtils qw( firstidx );
  use Log::Log4perl;
  use Exporter qw(import);

  our @EXPORT      = qw( event_role event_type );
  our %EXPORT_TAGS = (all_funcs => [ @EXPORT ]);

  our $logger = Log::Log4perl->get_logger(__PACKAGE__);

  sub event_role ($self, $roleNumber) {
    Readonly::Hash my %ROLE_MAP => (
      1  => 'Primary',
      5  => 'Bride',
      6  => 'Groom',
      11 => 'Father',
      12 => 'Mother',
    );

    return $ROLE_MAP{$roleNumber} if exists $ROLE_MAP{$roleNumber};
    $logger->logcroak("undefined roleNumber $roleNumber");
    return 'Unknown';
  }

  sub event_type ($self, $typeNumber, $string = '') {
    Readonly::Hash my %Type_Map => (
      0  => $string,
      1  => 'Marriage',
      6  => 'Engagement',
      7  => 'Divorce',
      12 => 'Birth',
      13 => 'Death',
      26 => 'Education',
      27 => 'Elected',
      31 => 'Graduation',
      37 => 'Occupation',
      40 => 'Property',
      43 => 'Retirement',
    );

    return $Type_Map{$typeNumber} if exists $Type_Map{$typeNumber};
    $logger->logcroak("undefined typeNumber $typeNumber");
    return 'Unknown';
  }

}
1;
__END__
