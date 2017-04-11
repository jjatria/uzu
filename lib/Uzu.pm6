use v6;

use IO::Notification::Recursive;
use File::Find;
use YAMLish;
use Terminal::ANSIColor;

unit module Uzu:ver<0.1.7>:auth<gitlab:samcns>;

#
# Logger
#

sub start-logger(
    Supplier $log = Supplier.new
    --> Block
) {
    start {
        react {
            whenever $log.Supply { say $_ }
        }
    }

    return -> $message, $l = $log {
        $l.emit: $message;
    }
}

#
# HTML Rendering
#

sub templates(
    List :$exts!,
    Str  :$dir!
    --> Seq
) {
    return $dir.IO.dir(:test(/:i ^ \w+ '.' |$exts $/));
}

sub build-context(
    Str :$i18n_dir,
    Str :$language
    --> Hash
) {
    my Str $i18n_file = "$i18n_dir/$language.yml";
    if $i18n_file.IO.f {
        try {
            CATCH {
                default {
                    note "Invalid i18n yaml file [$i18n_file]";
                }
            }
            return %( %(language => $language), load-yaml slurp($i18n_file) );
        }
    }
    return %( error => "i18n yaml file [$i18n_file] could not be loaded" );
}

sub write-generated-files(
    Hash $content,
    Str  :$build_dir
    --> Bool
) {
    # IO write to disk
    for $content.keys -> $path {
        spurt "$build_dir/$path.html", $content{$path}
    };
}

sub html-file-name(
    Str :$page_name,
    Str :$default_language,
    Str :$language
    --> Str
) {
    return "{$page_name}-{$language}" if $language !~~ $default_language;
    return $page_name;
}

sub process-livereload(
    Str  :$content,
    Bool :$no_livereload
    --> Str
) {
    unless $no_livereload {
        # Add livejs if live-reload enabled (default)
        my Str $livejs = '<script src="uzu/js/live.js"></script>';
        return $content.subst('</body>', "{$livejs}\n</body>");
    }
    return $content;
}

sub prepare-html-output(
    Hash $context,
    List :$template_dirs,
    Str  :$default_language,
    Str  :$language, 
    Hash :$pages,
    Bool :$no_livereload
    --> Hash
) {
    use Template6;
    my $t6 = Template6.new;

    $template_dirs.map(-> $dir {
        $t6.add-path: $dir
    });

    return gather {
        $pages.keys().map(-> $page_name {

            # Render the page content
            my Str $page_content = $t6.process($page_name, |$context);

            # Append page content to $context
            my %layout_context = %( |$context, %( content => $page_content ) );
            my Str $layout_content = $t6.process('layout', |%layout_context );

            # Default file_name without prefix
            my Str $file_name = 
                html-file-name(
                    page_name        => $page_name,
                    default_language => $default_language, 
                    language         => $language);

            # Return processed HTML
            my Str $processed_html =
                process-livereload(
                    content          => $layout_content,
                    no_livereload    => $no_livereload);

            take $file_name => $processed_html;

        })
    }.Hash;
};

our sub build(
    Map $config,
    ::D :&logger = start-logger()
    --> Bool
) {
    my Str $assets_dir = $config<assets_dir>;
    my Str $build_dir  = $config<build_dir>;

    # All available pages
    my List $exts = $config<extensions>;
    my IO::Path @page_templates = templates(exts => $exts, dir => $config<pages_dir>);

    my Str %pages = (@page_templates.map( -> $page { 
                         my Str $page_name = ( split '.', IO::Path.new($page).basename )[0]; 
                         %( $page_name => slurp $page, :r );
                     }));

    # Clear out build
    logger "Clear old files";
    qqx{ rm -rf $build_dir };

    # Create build dir
    if !$build_dir.IO.d { 
        logger "Create build directory";
        mkdir $build_dir;
    }

    # Copy assets
    logger "Copy asset files";
    qqx{ cp -rf $assets_dir/. $build_dir/ };

    # One per language
    await gather {
        $config<language>.map(-> $language { 
            take start {
                logger "Compile templates [$language]";
                build-context(
                    i18n_dir         => $config<i18n_dir>,
                    language         => $language
                ).&prepare-html-output(
                    template_dirs    => $config<template_dirs>,
                    default_language => $config<language>[0],
                    language         => $language,
                    pages            => %pages,
                    no_livereload    => $config<no_livereload>
                ).&write-generated-files(
                    build_dir        => $build_dir);
            }
        });
    }

    logger "Compile complete";
}

#
# Web Server
#

our sub serve(
    Str :$config_file
    --> Proc::Async
) {
    my Proc::Async $p;
    my @args = ("--config={$config_file}", "webserver");

    # Use the library path if running from test
    if "bin/uzu".IO.f {
        my IO::Path $lib_path = $?FILE.IO.parent;
        $p .= new: "perl6", "-I{$lib_path}", "bin/uzu", @args;
    } else {
        # Use uzu from PATH otherwise
        $p .= new: "uzu", @args;
    }

    my Promise $server-up .= new;
    $p.stdout.tap: -> $v { $*OUT.print: $v; }
    $p.stderr.tap: -> $v { 
        # Wait until server started
        if $server-up.status ~~ Planned {
            $server-up.keep if $v.contains('Started HTTP server');
        }
        # Filter out livereload requests
        if !$v.contains('GET /live') { $*ERR.print: $v }
    }

    # Start web server
    $p.start;

    # Wait for server to come online
    await $server-up;
    return $p;
}

our sub web-server(
    Map $config
    --> Bool
) {
    use Bailador;
    use Bailador::App;
    my Bailador::ContentTypes $content-types = Bailador::ContentTypes.new;
    my $build_dir = $config<build_dir>;

    # Use for triggering reload staging when reload is triggered
    my $channel = Channel.new;

    # When accessed, sets $reload to True
    get '/reload' => sub () {
        $channel.send(True);
        header("Content-Type", "application/json");
        return [ '{ "reload": "Staged" }' ];
    }

    # If $reload is True, return a JSON doc
    # instructing uzu/js/live.js to reload the
    # browser.
    get '/live' => sub () {
        header("Content-Type", "application/json");
        return ['{ "reload": "True"  }'] if $channel.poll;
        return ['{ "reload": "False" }'];
    }

    # Include live.js that starts polling /live
    # for reload instructions
    get '/uzu/js/live.js' => sub () {
        my Str $livejs = q:to/END/; 
        // Uzu live-reload
        function live() {
            var xhttp = new XMLHttpRequest();
            xhttp.onreadystatechange = function() {
                if (xhttp.readyState == 4 && xhttp.status == 200) {
                    var resp = JSON.parse(xhttp.responseText);
                    if (resp.reload == 'True') {
                        document.location.reload();
                    };
                };
            };
            xhttp.open("GET", "live", true);
            xhttp.send();
            setTimeout(live, 1000);
        }
        setTimeout(live, 1000);
        END
        #"

        header("Content-Type", "application/javascript");
        return [ $livejs ];
    }

    get /(.+)/ => sub ($file) {
        # Trying to access files outside of build path
        return "Invalid path" if $file.match('..');

        my IO::Path $path;
        if $file ~~ '/' {
            # Serve index.html on /
            $path = IO::Path.new("{$build_dir}/index.html");
        } else {
            # Strip query string for now
            $path = IO::Path.new("{$build_dir}{$file.split('?')[0]}");
        }

        # Invalid path
        return "Invalid path: file does not exists" if !$path.IO.e;

        # Return any valid paths
        my Str $type = $content-types.detect-type($path);
        header("Content-Type", $type);
        # UTF-8 text
        return slurp $path unless $type ~~ / image|ttf|woff|octet\-stream /;
        # Binary
        return slurp $path, :bin;
    }    

    # Start bailador
    baile($config<port>||3000);
}

sub reload-browser(
    $config,
    --> Bool()
) {
    unless $config<no_livereload> {
        use HTTP::Tinyish;
        HTTP::Tinyish.new().get("http://{$config<host>}:{$config<port>}/reload");
    }
}

#
# Event triggers
#

sub find-dirs(
    Str $p
    --> Slip
) {
    slip ($p.IO, slip find :dir($p), :type<dir>);
}

sub watch-dir(
    Str $p
    --> Tap
) {
    whenever IO::Notification.watch-path($p) -> $c {
        if $c.event ~~ FileRenamed && $c.path.IO ~~ :d {
            find-dirs($c.path).map(watch-dir $_);
        }
        emit $c;
    }
}

sub file-change-monitor(
    List $dirs
    --> Supply
) {
    supply {
        watch-dir(~$_) for $dirs.map: { find-dirs $_ };
    }
}

sub build-and-reload(
    $config,
    :&logger
    --> Bool
) {
    build($config, logger => &logger);
    reload-browser($config);
}

sub user-input(
    $config,
    :$app,
    :&logger
    --> Bool
) {
    loop {
        logger colored "Press `r enter` to [rebuild], `q enter` to [quit]", "bold green on_blue";
        given prompt('') {
            when 'r' {
                logger colored "Rebuild triggered", "bold green on_blue";
                build-and-reload($config, logger => &logger);
            }
            when 'q'|'quit' {
                $app.kill(SIGKILL);
                exit 1;
            }
        }
    }
}

our sub watch(
    Map  $config,
    --> Bool
) {
    my &logger = start-logger();
    
    # Initialize build
    logger "Initial build";
    build($config, logger => &logger);
    
    # Track time delta between FileChange events. 
    # Some editors trigger more than one event per
    # edit. 
    my List $exts = $config<extensions>;
    my List $dirs = |$config<template_dirs>.grep(*.IO.e);
    $dirs.map(-> $dir {
        logger "Starting watch on {$dir.subst("{$*CWD}/", '')}";
    });

    # Start server
    my Proc::Async $app = serve config_file => $config<path>;

    # Keep track of the last render timestamp
    my Instant $last_run = now;

    # Watch directories for modifications
    start {
        react {
            whenever file-change-monitor($dirs) -> $e {
                # Make sure the file change is a 
                # known extension; don't re-render too fast
                if so $e.path.IO.extension ∈ $exts and (now - $last_run) > 2 {
                    logger colored "Change detected [{$e.path()}]", "bold green on_blue";
                    build-and-reload($config, logger => &logger);
                    $last_run = now;
                }
            }
        }
    }

    # Listen for keyboard input
    user-input($config, app => $app, logger => &logger);
}

#
# Config
#

sub valid-project-folder-structure(
    @template_dirs
    --> Bool()
) {
    @template_dirs.grep({ !$_.IO.e }).&{
        unless elems $_ > 0 {
            note "Project directory missing: \n * {$_.join: "\n * "}";
            exit 1;
        }
    }();
}

sub parse-config(
    Str :$config_file
    --> Map()
) {
    return load-yaml(slurp($config_file)).Map when $config_file.IO.f;
    note "Config file [$config_file] not found. Please run uzu init to generate.";
    exit 1;
}

sub uzu-config(
    Str  :$config_file = 'config.yml',
    Bool :$no_livereload = False
    --> Map
) is export {

    # Gemeral config
    my Map  $config         = parse-config(config_file => $config_file);
    my List $language       = [$config<language>];

    # Network
    my Str  $host           = $config<host>||'0.0.0.0';
    my Int  $port           = $config<port>||3000;

    # Paths
    my Str  $project_root   = "{$config<project_root>||$*CWD}".subst('~', $*HOME);
    my Str  $build_dir      = "{$project_root}/build";
    my Str  $themes_dir     = "{$project_root}/themes";
    my Str  $assets_dir     = "{$project_root}/themes/{$config<defaults><theme>||'default'}/assets";
    my Str  $layout_dir     = "{$project_root}/themes/{$config<defaults><theme>||'default'}/layout";
    my Str  $pages_dir      = "{$project_root}/pages";
    my Str  $partials_dir   = "{$project_root}/partials";
    my Str  $i18n_dir       = "{$project_root}/i18n";
    my List $template_dirs  = [$layout_dir, $pages_dir, $partials_dir, $i18n_dir];
    my List $extensions     = ['tt', 'html', 'yml'];

    # Confirm all template directories exist
    # before continuing.
    valid-project-folder-structure($template_dirs);

    my Map $config_plus = (
        :host($host),
        :port($port),
        :language($language),
        :no_livereload($no_livereload),
        :project_root($project_root),
        :path($config_file),
        :build_dir($build_dir),
        :themes_dir($themes_dir),
        :assets_dir($assets_dir),
        :layout_dir($layout_dir),
        :pages_dir($pages_dir),
        :partials_dir($partials_dir),
        :i18n_dir($i18n_dir),
        :template_dirs($template_dirs),
        :extensions($extensions)
    ).Map;

    # We want to stop everything if the project root ~~ $*HOME or
    # the build dir ~~ project root. This would have bad side-effects
    if $build_dir.IO ~~ $*HOME.IO|$project_root.IO {
        note "Build directory [{$build_dir}] cannot be {$*HOME} or project root [{$project_root}].";
        exit(1);
    }

    # Merged config as output
    return Map.new($config.pairs, $config_plus.pairs);
}

#
# Init
#

our sub init(
    Str  :$config_file  = 'config.yml', 
    Str  :$project_name = 'New Uzu Project',
    Str  :$url          = 'http://example.com',
    Str  :$language     = 'en',
    Str  :$theme        = 'default'
    --> Bool
) {
    my Map $config = (
        :name($project_name),
        :url($url),
        :language($language),
        :theme($theme)
    ).Map;

    my Str $theme_dir      = "themes/$theme";
    my List $template_dirs = (
        "i18n", 
        "pages",
        "partials",
        "$theme_dir/layout",
        "$theme_dir/assets"
    );

    # Create project directories
    $template_dirs.map( -> $dir { mkdir $dir });

    # Write config file
    my Str $config_yaml = S:g /'...'// given save-yaml($config);
    my Str $config_out  = S:g /'~'/$*HOME/ given $config_file;
    return spurt $config_out, $config_yaml;
}

# License
# 
# This module is licensed under the same license as Perl6 itself. 
# Artistic License 2.0.
#
# Copyright 2017 Sam Morrison.

# vim: ft=perl6
