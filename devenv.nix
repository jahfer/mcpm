{ pkgs, nixpkgs-ruby, lib, config, ... }:

{
  packages = [
    pkgs.git
    pkgs.libyaml
  ];

  languages.ruby = {
    enable = true;
    package = nixpkgs-ruby.packages.${pkgs.system}."ruby-4.0.2";
    bundler.enable = true;
  };

  tasks = {
    "bundle:install" = {
      exec = "bundle install";
      description = "Install gem dependencies";
      before = [ "devenv:enterShell" ];
      status = "bundle check > /dev/null 2>&1";
    };

    "mcpm:test" = {
      exec = ''
        if [ -z "$1" ]; then
          bin/testunit
        elif [ -z "$2" ]; then
          bundle exec ruby -Itest "$1"
        else
          bundle exec ruby -Itest "$1" --name "$2"
        fi
      '';
      description = "Run tests";
      after = [ "bundle:install" ];
    };
  };
}
