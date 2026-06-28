defmodule Delfos.Syntax.Dockerfile do
  alias Alaja.Syntax.{Language, Special}

  def definition do
    %Language{
      name: "Dockerfile",
      line_comment: "#",
      strings: [
        %{delim: ~r/"/, end: ~r/"/, escape: true},
        %{delim: ~r/'/, end: ~r/'/, escape: true}
      ],
      keywords: MapSet.new(~w(
        FROM RUN CMD ENTRYPOINT COPY ADD ENV ARG WORKDIR
        EXPOSE VOLUME LABEL MAINTAINER USER SHELL STOPSIGNAL
        HEALTHCHECK ONBUILD
      )),
      types: MapSet.new(),
      operators: MapSet.new(["=", "|"]),
      specials: [
        %Special{pattern: ~r/\$\{?\w+\}?/, type: :variable, priority: 10}
      ],
      module_separator: "",
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
