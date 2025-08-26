use v5.42.0;
use experimental qw(class);
use utf8::all;
require DBD::SQLite;
require DBI;
require Data::Printer;
require GraphViz;
require JSON::PP;
require Path::Tiny;
require XML::LibXML;
require App::Schierer::HPFan::Logger::Config;
use namespace::autoclean;

class App::Schierer::HPFan::Data :isa(App::Schierer::HPFan::Logger){
  use Carp;
  use Log::Log4perl;
  use List::AllUtils qw( first any );
  use DBD::SQLite::Constants qw/:dbd_sqlite_string_mode/;
  our $VERSION = 'v0.0.1';

  field $dbh;
  field $gramps_db  : param;
  field $output     : param;
  field $debug      : param = 0;
  field $logger;

  ADJUST {
    my $lc =
      App::Schierer::HPFan::Logger::Config->new('App::Schierer::HPFan::Data');

    if ($debug) {
      my $log4perl_logger = $lc->init('development');
    }
    else {
      my $log4perl_logger = $lc->init('testing');
    }

    $logger = Log::Log4perl->get_logger(__CLASS__);
  }


  ADJUST {
    # Do not assume we are passed a Path::Tiny object;
    $output = Path::Tiny::path($output);
    if(!$output->is_dir) {
      $self->logger->logcroak("output directory $output is not a directory.");
    }
    $gramps_db = Path::Tiny::path($gramps_db);
    if (!$gramps_db->is_file) {
      $self->logger->logcroak("gramps_db $gramps_db is not a file.");
    }
    else {
      $dbh = DBI->connect(
        "dbi:SQLite:$gramps_db",
        undef, undef,
        {
          RaiseError => 1,
          AutoCommit => 1,    #fallback just in case
        }
      );
      $self->logger->logcroak(
        "unsuccessfull connecting to $gramps_db. error: " . $DBI::errstr)
        unless ($dbh);
      $dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_FALLBACK;
      # One-time-ish setup (safe if repeated)
      $dbh->do('PRAGMA journal_mode=WAL');     # persistent per DB
      $dbh->do('PRAGMA synchronous=NORMAL');   # performance tradeoff ok for dev
      $dbh->do('PRAGMA temp_store=MEMORY');

      # Now forbid writes on THIS connection:
      $dbh->do('PRAGMA query_only=ON');        # connection-level read-only
          # Optional: longer busy timeout to handle writer checkpoints
      $dbh->do('PRAGMA busy_timeout=3000');
    }
  }

  method execute {
     $self->logger->info("App::Schierer::HPFan::Data starting processing of $gramps_db");
     $self->get_person_data();
  }

  method get_person_data {
    my $people = $output->child('people');
    $people->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of person table");
    $self->_get_data_with_gramps_id('person', $people);
    $self->logger->debug("finished processing of person table");
  }

  method get_family_data {
    my $families = $output->child('families');
    $families->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of family table");
    $self->_get_data_with_gramps_id('family', $families);
    $self->logger->debug("finished processing of family table");
  }

  method get_citation_data {
    my $citations = $output->child('citations');
    $citations->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of citation table");
    $self->_get_data_with_gramps_id('citation', $citations);
    $self->logger->debug("finished processing of citation table");
  }

  method get_source_data {
    my $sources = $output->child('sources');
    $sources->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of source table");
    $self->_get_data_with_gramps_id('source', $sources);
    $self->logger->debug("finished processing of source table");
  }

  method get_event_data {
    my $events = $output->child('events');
    $events->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of event table");
    $self->_get_data_with_gramps_id('event', $events);
    $self->logger->debug("finished processing of event table");
  }

  method get_note_data {
    my $notes = $output->child('notes');
    $notes->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of note table");
    $self->_get_data_with_gramps_id('note', $notes);
    $self->logger->debug("finished processing of note table");
  }

  method get_reference_data {
    my $references = $output->child('references');
    $references->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of reference table");
    $self->_get_data_with_gramps_id('reference', $references);
    $self->logger->debug("finished processing of reference table");
  }

  method get_tag_data {
    my $tags = $output->child('tags');
    $tags->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of tag table");
    $self->_get_data_with_gramps_id('tag', $tags);
    $self->logger->debug("finished processing of tag table");
  }

  method get_repository_data {
    my $repositorys = $output->child('repositorys');
    $repositorys->mkdir({ mode => 0750 });

    $self->logger->info("starting processing of repository table");
    $self->_get_data_with_gramps_id('repository', $repositorys);
    $self->logger->debug("finished processing of repository table");
  }

  method _get_data_with_gramps_id($tableName, $target){
    my @tableNames = qw(
    citation      gender_stats  name_group    place         source
    event         media         note          reference     tag
    family        metadata      person        repository
    );
    unless (any { $_ eq $tableName } @tableNames) {
      $self->logger->error(sprintf('tableName %s must be one of %s',
      $tableName, join(' ', @tableNames) ));
      return;
    }
    my $all_entries = $dbh->selectcol_arrayref("SELECT gramps_id FROM ${tableName}");

    foreach my $entry (@$all_entries) {
      $self->logger->debug(" processing $entry");
      my $sql = "SELECT json_data FROM $tableName WHERE gramps_id = ?";
      my $result = $dbh->selectrow_hashref($sql, undef, $entry);
      my $hash = JSON::PP->new->decode($result->{'json_data'});
      $self->logger->debug(sprintf('hash of %s is %s', $entry, Data::Printer::np($hash)));
      my $entry_target = $target->child("${entry}.json");
      $entry_target->spew_utf8(JSON::PP->new->utf8->pretty->canonical->encode($hash));
    }
  }

}
1;
__END__
