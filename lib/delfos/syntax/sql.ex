defmodule Delfos.Syntax.Sql do
  alias Alaja.Syntax.Language

  def definition do
    %Language{
      name: "SQL",
      line_comment: "--",
      block_comment: %{start: "/*", end: "*/"},
      strings: [
        %{delim: ~r/'/, end: ~r/'/, escape: true},
        %{delim: ~r/"/, end: ~r/"/, escape: true}
      ],
      number: ~r/\b\d[\d_.]*(f|l|u)?\b/,
      keywords: MapSet.new(~w(
        SELECT FROM WHERE INSERT INTO VALUES UPDATE SET DELETE
        JOIN INNER LEFT RIGHT OUTER FULL CROSS ON AND OR NOT IN
        BETWEEN LIKE ILIKE IS NULL EXISTS AS DISTINCT GROUP BY
        HAVING ORDER ASC DESC LIMIT OFFSET UNION ALL
        CREATE TABLE ALTER DROP ADD COLUMN CONSTRAINT PRIMARY KEY
        FOREIGN REFERENCES INDEX VIEW FUNCTION PROCEDURE TRIGGER
        CASCADE SET NULL DEFAULT UNIQUE CHECK GRANT REVOKE
        COMMIT ROLLBACK BEGIN TRANSACTION SAVEPOINT
        DECLARE CURSOR FETCH CLOSE OPEN EXECUTE
        CAST CONVERT COALESCE NULLIF CASE WHEN THEN ELSE END
        TRUE FALSE
      )),
      types: MapSet.new(~w(
        INT INTEGER BIGINT SMALLINT TINYINT SERIAL
        NUMERIC DECIMAL FLOAT REAL DOUBLE PRECISION MONEY
        VARCHAR CHAR TEXT BOOLEAN BOOL DATE TIME TIMESTAMP
        TIMESTAMPTZ INTERVAL BYTEA BLOB CLOB UUID JSON JSONB
        ARRAY ENUM GEOMETRY POINT
      )),
      operators:
        MapSet.new([
          "=",
          "<>",
          "!=",
          "<",
          ">",
          "<=",
          ">=",
          "||",
          "+",
          "-",
          "*",
          "/",
          "%",
          "AND",
          "OR",
          "NOT",
          "IN",
          "BETWEEN",
          "LIKE",
          "ILIKE",
          "SIMILAR",
          "IS",
          "NULL",
          "EXISTS",
          "ANY",
          "ALL",
          "SOME",
          "@>",
          "<@",
          "?",
          "?|",
          "?&",
          "#-",
          "->",
          "->>"
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
        macro: {:magenta, [:bold]},
        variable: {:red, []},
        plain: {:white, []}
      }
    }
  end
end
