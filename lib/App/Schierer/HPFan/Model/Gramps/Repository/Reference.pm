use v5.42;
use utf8::all;
use experimental qw(class);
require Scalar::Util;
require App::Schierer::HPFan::Model::Gramps::Source::MediaType;

class App::Schierer::HPFan::Model::Gramps::Repository::Reference :
  isa(App::Schierer::HPFan::Model::Gramps::Reference) {
  use Carp;

  field $call_number : param : reader = undef;
  field $media_type  : param : reader = undef;

  ADJUST {
    if (defined($media_type)) {
      my $type = Scalar::Util::blessed($media_type) // '';
      if ($type ne 'App::Schierer::HPFan::Model::Gramps::Source::MediaType') {
        $media_type =
          App::Schierer::HPFan::Model::Gramps::Source::MediaType->new(
          $media_type->%*);
      }
    }
  }

}
1;
__END__
