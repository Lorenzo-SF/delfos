defmodule Delfos.Syntax.Gradle do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "Gradle",
      line_comment: "//",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(e[+-]?\d+)?\b/,
      keywords: MapSet.new(~w(
        project task dependencies repositories buildscript plugins apply
        group name version description sourceCompatibility targetCompatibility
        compileJava compileTestJava processResources jar test war bootJar
        bootWar shadowJar configurations implementation api compileOnly
        runtimeOnly testImplementation testCompileOnly testRuntimeOnly
        annotationProcessor allprojects subprojects configure
        evaluateDependsOn beforeEvaluate afterEvaluate ext defaultTasks clean
        check build assemble uploadArchives publishing maven mavenCentral
        jcenter google flatDir ivy
      )),
      types: MapSet.new(~w(
        Task Configuration Dependency Publication Artifact ResolutionStrategy
        CopySpec FileTree FileCollection Provider Property RegularFile
        Directory File
      )),
      operators:
        MapSet.new([
          "=",
          "<<",
          "->",
          "+=",
          "-=",
          "?.",
          "::"
        ]),
      specials: [],
      module_separator: ".",
      colors: %{
        keyword: {:blue, [:bold]},
        string: {:green, []},
        comment: {:bright_black, [:italic]},
        number: {:cyan, []},
        type: {:cyan, []},
        operator: {:white, []},
        module: {:magenta, []},
        decorator: {:yellow, []},
        builtin: {:cyan, []},
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
