use v6;

use Uzu::Config;
use Uzu::HTTP;
use Uzu::Render;
use Uzu::Watch;

sub USAGE is export {
  say q:to/END/;
      Usage:
        uzu init          - Initialize new project
        uzu webserver     - Start local web server
        uzu build         - Render all templates to build
        uzu watch         - Start web server and re-render
                            build on template modification
        uzu version       - Print uzu version and exit

      Optional arguments:
        
        --config=         - Specify a custom config file
                            Default is `config`

        e.g. uzu --config=path/to/config.yml init 

        --no-livereload   - Disable livereload when
                            running uzu watch.
      END
}

multi MAIN('config', Str :$config = 'config.yml') is export {
  say Uzu::Config::from-file(config_file => $config.IO);
}

multi MAIN('webserver', Str :$config = 'config.yml') is export {
  Uzu::Config::from-file(config_file => $config.IO).&Uzu::HTTP::web-server();
}

multi MAIN('build', Str :$config = 'config.yml') is export {
  Uzu::Config::from-file(
      config_file => $config.IO,
      no_livereload => True
  ).&Uzu::Render::build();
}

multi MAIN('watch', Str :$config = 'config.yml', Bool :$no-livereload) is export {
  Uzu::Config::from-file(
      config_file   => $config.IO,
      no_livereload => ($no-livereload ?? True !! False)
  ).&Uzu::Watch::start();
}

multi MAIN('init', Str :$config = 'config.yml') is export {

  # config file exists, exit
  return say "Config [$config] already exists." if $config.IO ~~ :f;

  say "Uzu project initialization";
  my $project_name = prompt("Please enter project name: ");
  my $url          = prompt("Please enter project url (e.g http://example.com): ");
  my $language     = prompt("Please enter project language (e.g. en, ja): ");
  my $theme        = prompt("Please enter project theme (e.g. default): ")||"default";

  if Uzu::Config::init
      config_file  => $config.IO,
      project_name => $project_name,
      url          => $url,
      language     => $language,
      theme        => $theme {
    say "Config [$config] successfully created.";
  }
}

multi MAIN('version') is export {
  say "uzu {Uzu.^ver}";
}
