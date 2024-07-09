{pkgs, ...}: let
  pname = "title-case";
  src = pkgs.writeTextFile {
    name = "${pname}.py";
    text = ''
      #!/usr/bin/env python3
      from re import compile, IGNORECASE
      from sys import stdin
      def apa_title(text):
          words = text.split()
          small_words = compile(r"\b(a|an|and|as|at|but|by|for|in|of|on|or|the|to)\b", IGNORECASE)
          for i, word in enumerate(words):
              if i == 0 or i == len(words) - 1 or not small_words.match(word):
                  text = text.replace(word, word.title())
              else:
                  text = text.replace(word, word.lower())
          return text
      if __name__ == "__main__":
          for line in stdin:
              print(apa_title(line), end="")
    '';
  };
in
  pkgs.python312Packages.buildPythonApplication {
    inherit pname src;
    version = "1.0.0";
    format = "other";
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/${pname}.py
      chmod +x $out/bin/${pname}.py
    '';
  }
