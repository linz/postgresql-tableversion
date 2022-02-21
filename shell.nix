{ pkgs ? import
    (
      fetchTarball {
        name = "21.11";
        url = "https://github.com/NixOS/nixpkgs/archive/a7ecde854aee5c4c7cd6177f54a99d2c1ff28a31.tar.gz";
        sha256 = "162dywda2dvfj1248afxc45kcrg83appjd0nmdb541hl7rnncf02";
      })
    { }
}:
let
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
