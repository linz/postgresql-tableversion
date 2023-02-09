let
  pkgs =
    import
      (
        fetchTarball (
          builtins.fromJSON (
            builtins.readFile ./nixpkgs.json
          )
        )
      )
      { };
  postgresql = pkgs.postgresql;
  pg_prove = pkgs.stdenv.mkDerivation {
    name = "pg_prove";

    nativeBuildInputs = [ pkgs.makeWrapper ];

    phases = [ "installPhase" ];

    installPhase = ''
      mkdir -p $out/bin
      makeWrapper ${pkgs.perlPackages.TAPParserSourceHandlerpgTAP}/bin/pg_prove $out/bin/pg_prove \
        --prefix PATH : ${pkgs.lib.makeBinPath [ postgresql ]}
      makeWrapper ${pkgs.perlPackages.TAPParserSourceHandlerpgTAP}/bin/pg_tapgen $out/bin/pg_tapgen \
        --prefix PATH : ${pkgs.lib.makeBinPath [ postgresql ]}
    '';
  };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.cacert
    pkgs.cargo
    pkgs.docker
    pkgs.gitFull
    pkgs.gnumake
    pkgs.nodejs
    (postgresql.withPackages (ps: [
      ps.pgtap
      pg_prove
    ]))
    pkgs.pre-commit
    pkgs.which
  ];
}
