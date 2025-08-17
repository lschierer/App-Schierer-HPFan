use v5.42;
use utf8::all;
use experimental qw(class);
require Date::Manip;
require App::Schierer::HPFan::Model::Gramps::DateHelper;
require App::Schierer::HPFan::Model::Gramps::Object::Reference;
require App::Schierer::HPFan::Model::Gramps::Source::Reference;

class App::Schierer::HPFan::Model::Gramps::Citation :
  isa(App::Schierer::HPFan::Model::Gramps::Generic) {
  use Carp;
  require App::Schierer::HPFan::Model::Gramps::DateHelper;

  field $id         : reader : param = undef;
  field $priv       : reader : param = undef;
  field $page       : reader : param = '';
  field $confidence : reader : param = 0;
  field $date       : param = undef;

  field $source_refs   : param //= [];
  field $obj_refs      : param //= [];
  field $srcattributes : param = [];

  field $dh = App::Schierer::HPFan::Model::Gramps::DateHelper->new();
  field $ALLOWED_FIELD_NAMES : reader =
    { map { $_ => 1 } qw( gramps_id change private json_data) };

  method source_refs()   { [@$source_refs] }
  method obj_refs()      { [@$obj_refs] }
  method srcattributes() { [@$srcattributes] }

  method date {
    return $date->to_string;
  }

}
1;
__END__
