use v5.42;
use experimental qw(class);

class App::Schierer::HPFan::Model::History::Event {
  # Uniform interface every event must provide
  field $id         :param :reader;   # stable key (e.g. "G:E0234" or "Y:file#anchor")
  field $origin     :param :reader;   # 'gramps' | 'yaml'
  field $type       :param :reader;   # free text like "Birth" | "Battle" | ...
  field $blurb      :param :reader;   # 1–2 line teaser (optional)
  field $date_iso   :param :reader;   # "YYYY[-MM[-DD]]" (partial ok)
  field $date_kind  :param :reader;   # '', 'before', 'after', 'about', 'between', 'from', 'estimated', 'calculated'
  field $sortval    :param :reader;   # numeric sort key (e.g. gramps sortval / computed)
  field $html_desc  :param :reader :writer;   # pre-rendered HTML (or undef; see lazy below)
  field $sources    :param :reader :writer;   # arrayref of sources (structs/strings)

  method as_hashref {
    return {
      id        => $id,
      origin    => $origin,
      type      => $type,
      title     => $title,
      blurb     => $blurb,
      date_iso  => $date_iso,
      date_kind => $date_kind,
      sortval   => $sortval,
      sources   => $sources,
    };
  }
}
