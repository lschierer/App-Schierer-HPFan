use Module::Build;

my $build = Module::Build->new(
    module_name                 => 'App::Schierer::HPFan',
    license                     => 'CC_BY_NC_4_0',
    dist_author                 => 'Luke Schierer <luke@schierer.org>',
    dist_version_from           => 'lib/App/Schierer/HPFan.pm',
    dist_abstract               => 'Create, Build, Run the Mojolicious based HPFan.schierer.org site',
    requires                    => {
        'perl'                  => '5.42.0', # Minimum Perl version
        'Carp'                  => '0',
        'File::FindLib'         => '0',
        'Log::Log4perl'         => '0',
        'Log::Log4perl::Config' => '0',
        'Mojo::Base'            => '0',
        'Mojo::Home'            => '0',
        'Mojo::File::Share'     => '0',
        'Path::Tiny'            => '0',
        'utf8::all'             => '0',
    },
    test_requires               => {
      'Test::More'              => '0',
    },
    build_requires              => {
      'Devel::Local'            => '0',
      'Mojolicious::Command::Author::generate' => '0',
    },
    add_to_cleanup              => [ 'App-Schierer-HPFan-*' ],
    create_license              => 1,
    create_readme               => 1,
);

$build->create_build_script();
