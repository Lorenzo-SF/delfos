defmodule Delfos.LLM.FrameworkContext do
  @moduledoc """
  Detecta el framework usado por un símbolo o proyecto para enriquecer
  los prompts del LLM con contexto específico del stack tecnológico.

  La detección usa tres señales en orden de precisión:
    1. metadata[:framework] — si el parser lo detectó explícitamente
    2. Contenido del símbolo — patrones de imports/decoradores/macros
    3. Ficheros raíz del proyecto — mix.exs, package.json, Cargo.toml, etc.
  """

  # ---------------------------------------------------------------------------
  # API principal
  # ---------------------------------------------------------------------------

  @doc """
  Devuelve una frase de contexto de framework para incluir en prompts LLM.
  Ejemplo: "using Phoenix LiveView with Ecto schemas"
  """
  def for_symbol(language, metadata, content \\ "") do
    metadata_str = if is_map(metadata), do: metadata, else: %{}
    detect(language, metadata_str, content || "")
  end

  @doc """
  Devuelve el framework detectado para todo el proyecto.
  Inspecciona los ficheros raíz del directorio.
  """
  def for_project(project_path) do
    cond do
      File.exists?("#{project_path}/mix.exs") ->
        detect_elixir_project(project_path)

      File.exists?("#{project_path}/package.json") ->
        detect_node_project(project_path)

      File.exists?("#{project_path}/Cargo.toml") ->
        "Rust"

      File.exists?("#{project_path}/go.mod") ->
        "Go"

      File.exists?("#{project_path}/pom.xml") ->
        "Java/Maven"

      File.exists?("#{project_path}/build.gradle") or
          File.exists?("#{project_path}/build.gradle.kts") ->
        "Kotlin/Gradle or Java/Gradle"

      File.exists?("#{project_path}/pubspec.yaml") ->
        "Dart/Flutter"

      File.exists?("#{project_path}/pyproject.toml") or
          File.exists?("#{project_path}/requirements.txt") ->
        detect_python_project(project_path)

      File.exists?("#{project_path}/Gemfile") ->
        detect_ruby_project(project_path)

      File.exists?("#{project_path}/composer.json") ->
        "PHP/Laravel or Symfony"

      File.exists?("#{project_path}/*.sln") or File.exists?("#{project_path}/*.csproj") ->
        "C#/.NET"

      true ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Detección por lenguaje
  # ---------------------------------------------------------------------------

  defp detect("elixir", meta, content) do
    cond do
      meta["framework"] == "phoenix" ->
        elixir_phoenix_hint(content)

      meta["umbrella"] == true ->
        "in an Elixir umbrella app"

      String.contains?(content, "use Phoenix") ->
        elixir_phoenix_hint(content)

      String.contains?(content, "use Ecto.Schema") ->
        "using Ecto schema (database layer)"

      String.contains?(content, "use GenServer") ->
        "implementing a GenServer OTP process"

      String.contains?(content, "use Supervisor") ->
        "implementing an OTP Supervisor"

      String.contains?(content, "use Agent") ->
        "implementing an OTP Agent"

      String.contains?(content, "use Task") ->
        "using OTP Task for async work"

      String.contains?(content, "use Broadway") ->
        "using Broadway for message processing pipelines"

      String.contains?(content, "use Oban") ->
        "using Oban for background job processing"

      String.contains?(content, "use Absinthe") ->
        "using Absinthe GraphQL"

      true ->
        "in Elixir/OTP"
    end
  end

  defp detect("typescript", _meta, content) do
    cond do
      String.contains?(content, "@Component") and String.contains?(content, "selector") ->
        "using Angular (component)"

      String.contains?(content, "@Injectable") ->
        "using Angular/NestJS dependency injection"

      String.contains?(content, "@Controller") or String.contains?(content, "@Get(") ->
        "using NestJS REST controller"

      String.contains?(content, "useState") or String.contains?(content, "useEffect") ->
        "using React (functional component with hooks)"

      String.contains?(content, "React.Component") ->
        "using React (class component)"

      String.contains?(content, "defineComponent") or String.contains?(content, "ref(") ->
        "using Vue 3 Composition API"

      String.contains?(content, "Vue.component") ->
        "using Vue 2"

      String.contains?(content, "createSlice") or String.contains?(content, "createReducer") ->
        "using Redux Toolkit"

      String.contains?(content, "express()") or String.contains?(content, "app.get(") ->
        "using Express.js"

      String.contains?(content, "fastify") ->
        "using Fastify"

      String.contains?(content, "prisma") ->
        "using Prisma ORM"

      String.contains?(content, "drizzle") ->
        "using Drizzle ORM"

      String.contains?(content, "next/") ->
        "using Next.js"

      String.contains?(content, "nuxt") ->
        "using Nuxt.js"

      true ->
        "in TypeScript/Node.js"
    end
  end

  defp detect("javascript", meta, content), do: detect("typescript", meta, content)

  defp detect("python", _meta, content) do
    cond do
      String.contains?(content, "@app.route") or String.contains?(content, "Flask") ->
        "using Flask web framework"

      String.contains?(content, "@router.") or String.contains?(content, "FastAPI") ->
        "using FastAPI (async REST)"

      String.contains?(content, "from django") or String.contains?(content, "Django") ->
        detect_django_layer(content)

      String.contains?(content, "sqlalchemy") or String.contains?(content, "SQLAlchemy") ->
        "using SQLAlchemy ORM"

      String.contains?(content, "pydantic") ->
        "using Pydantic for data validation"

      String.contains?(content, "celery") ->
        "using Celery for async tasks"

      String.contains?(content, "pytest") ->
        "in a pytest test module"

      String.contains?(content, "torch") or String.contains?(content, "tensorflow") ->
        "in a machine learning module"

      true ->
        "in Python"
    end
  end

  defp detect("ruby", _meta, content) do
    cond do
      String.contains?(content, "< ApplicationController") ->
        "using Ruby on Rails (controller)"

      String.contains?(content, "< ActiveRecord::Base") or
          String.contains?(content, "< ApplicationRecord") ->
        "using Rails ActiveRecord model"

      String.contains?(content, "include Devise") ->
        "using Devise for authentication"

      String.contains?(content, "Sidekiq") ->
        "using Sidekiq for background jobs"

      true ->
        "in Ruby"
    end
  end

  defp detect("php", _meta, content) do
    cond do
      String.contains?(content, "extends Controller") ->
        "using Laravel controller"

      String.contains?(content, "extends Model") or
          String.contains?(content, "Eloquent") ->
        "using Laravel Eloquent ORM"

      String.contains?(content, "Route::") ->
        "in a Laravel routes file"

      String.contains?(content, "extends AbstractController") ->
        "using Symfony controller"

      String.contains?(content, "#[Route(") ->
        "using Symfony routing attributes"

      true ->
        "in PHP"
    end
  end

  defp detect("java", _meta, content) do
    cond do
      String.contains?(content, "@RestController") or String.contains?(content, "@Controller") ->
        "using Spring MVC/Boot controller"

      String.contains?(content, "@Service") ->
        "using Spring Service component"

      String.contains?(content, "@Repository") ->
        "using Spring Data repository"

      String.contains?(content, "@Entity") ->
        "using JPA entity (Hibernate)"

      String.contains?(content, "@SpringBootApplication") ->
        "Spring Boot application entry point"

      String.contains?(content, "extends Activity") ->
        "using Android Activity"

      String.contains?(content, "extends Fragment") ->
        "using Android Fragment"

      true ->
        "in Java"
    end
  end

  defp detect("kotlin", _meta, content) do
    cond do
      String.contains?(content, "@Composable") -> "using Jetpack Compose UI"
      String.contains?(content, "ViewModel()") -> "using Android ViewModel (MVVM)"
      String.contains?(content, "suspend fun") -> "using Kotlin coroutines"
      String.contains?(content, "@RestController") -> "using Spring Boot (Kotlin)"
      String.contains?(content, "Fragment()") -> "using Android Fragment"
      true -> "in Kotlin"
    end
  end

  defp detect("dart", _meta, content) do
    cond do
      String.contains?(content, "extends StatelessWidget") ->
        "using Flutter StatelessWidget"

      String.contains?(content, "extends StatefulWidget") or
          String.contains?(content, "extends State<") ->
        "using Flutter StatefulWidget"

      String.contains?(content, "ChangeNotifier") ->
        "using Flutter Provider/ChangeNotifier"

      String.contains?(content, "BlocBase") or String.contains?(content, "Cubit") ->
        "using Flutter BLoC/Cubit state management"

      String.contains?(content, "Riverpod") or String.contains?(content, "ref.watch") ->
        "using Flutter Riverpod state management"

      String.contains?(content, "GetX") ->
        "using Flutter GetX"

      true ->
        "in Dart/Flutter"
    end
  end

  defp detect("swift", _meta, content) do
    cond do
      String.contains?(content, "struct") and String.contains?(content, "View {") ->
        "using SwiftUI View"

      String.contains?(content, "@ObservableObject") or String.contains?(content, "@Published") ->
        "using SwiftUI ObservableObject"

      String.contains?(content, "UIViewController") ->
        "using UIKit ViewController"

      String.contains?(content, "UITableView") ->
        "using UIKit TableView"

      true ->
        "in Swift"
    end
  end

  defp detect("rust", _meta, content) do
    cond do
      String.contains?(content, "actix_web") or String.contains?(content, "#[get(") ->
        "using Actix-web"

      String.contains?(content, "axum") ->
        "using Axum web framework"

      String.contains?(content, "rocket") ->
        "using Rocket web framework"

      String.contains?(content, "tokio") ->
        "using Tokio async runtime"

      String.contains?(content, "diesel") ->
        "using Diesel ORM"

      String.contains?(content, "sqlx") ->
        "using SQLx"

      true ->
        "in Rust"
    end
  end

  defp detect("go", _meta, content) do
    cond do
      String.contains?(content, "gin.") or String.contains?(content, "gin.Context") ->
        "using Gin web framework"

      String.contains?(content, "fiber.") ->
        "using Fiber web framework"

      String.contains?(content, "http.Handler") or String.contains?(content, "http.HandlerFunc") ->
        "using net/http standard library"

      String.contains?(content, "gorm.") ->
        "using GORM ORM"

      String.contains?(content, "grpc.") ->
        "using gRPC"

      true ->
        "in Go"
    end
  end

  defp detect("csharp", _meta, content) do
    cond do
      String.contains?(content, "[ApiController]") or
          String.contains?(content, ": ControllerBase") ->
        "using ASP.NET Core Web API"

      String.contains?(content, ": Controller") ->
        "using ASP.NET MVC Controller"

      String.contains?(content, "DbContext") ->
        "using Entity Framework Core"

      String.contains?(content, "[Fact]") or String.contains?(content, "[Test]") ->
        "in xUnit/NUnit test"

      true ->
        "in C#/.NET"
    end
  end

  defp detect("terraform", _meta, _content), do: "defining Terraform infrastructure (IaC)"

  defp detect("config", _meta, content) do
    cond do
      String.contains?(content, "apiVersion:") ->
        "defining Kubernetes manifest"

      String.contains?(content, "helm.sh") ->
        "defining Helm chart values"

      String.contains?(content, "github.com/actions") or String.contains?(content, "runs-on:") ->
        "defining GitHub Actions workflow"

      String.contains?(content, "stages:") and String.contains?(content, "script:") ->
        "defining GitLab CI pipeline"

      String.contains?(content, "docker-compose") ->
        "defining Docker Compose services"

      true ->
        "in YAML configuration"
    end
  end

  defp detect(_, _, _), do: nil

  # ---------------------------------------------------------------------------
  # Helpers de detección refinada
  # ---------------------------------------------------------------------------

  defp elixir_phoenix_hint(content) do
    cond do
      String.contains?(content, "use Phoenix.LiveView") ->
        "using Phoenix LiveView"

      String.contains?(content, "use Phoenix.LiveComponent") ->
        "using Phoenix LiveComponent"

      String.contains?(content, "use Phoenix.Controller") ->
        "using Phoenix Controller"

      String.contains?(content, "use Phoenix.Router") ->
        "using Phoenix Router"

      String.contains?(content, "use Phoenix.Channel") ->
        "using Phoenix Channel (WebSocket)"

      String.contains?(content, "schema ") and String.contains?(content, "use Ecto") ->
        "using Phoenix with Ecto schema"

      true ->
        "using Phoenix Framework"
    end
  end

  defp detect_django_layer(content) do
    cond do
      String.contains?(content, "models.Model") ->
        "using Django ORM model"

      String.contains?(content, "APIView") or String.contains?(content, "ViewSet") ->
        "using Django REST Framework"

      String.contains?(content, "TemplateView") or String.contains?(content, "ListView") ->
        "using Django class-based view"

      String.contains?(content, "admin.ModelAdmin") ->
        "using Django admin"

      true ->
        "using Django"
    end
  end

  defp detect_elixir_project(path) do
    mix =
      File.read("#{path}/mix.exs")
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    cond do
      String.contains?(mix, ":phoenix") -> "Elixir/Phoenix"
      String.contains?(mix, ":nerves") -> "Elixir/Nerves (embedded)"
      String.contains?(mix, ":broadway") -> "Elixir/Broadway (data pipelines)"
      true -> "Elixir/OTP"
    end
  end

  defp detect_node_project(path) do
    pkg =
      File.read("#{path}/package.json")
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    cond do
      String.contains?(pkg, "\"next\"") -> "TypeScript/Next.js"
      String.contains?(pkg, "\"nuxt\"") -> "TypeScript/Nuxt.js"
      String.contains?(pkg, "\"@angular/core\"") -> "TypeScript/Angular"
      String.contains?(pkg, "\"react\"") -> "TypeScript/React"
      String.contains?(pkg, "\"vue\"") -> "TypeScript/Vue"
      String.contains?(pkg, "\"@nestjs/core\"") -> "TypeScript/NestJS"
      String.contains?(pkg, "\"express\"") -> "Node.js/Express"
      true -> "Node.js/TypeScript"
    end
  end

  defp detect_python_project(path) do
    req =
      File.read("#{path}/requirements.txt")
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    pyproject =
      File.read("#{path}/pyproject.toml")
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    content = req <> pyproject

    cond do
      String.contains?(content, "django") ->
        "Python/Django"

      String.contains?(content, "fastapi") ->
        "Python/FastAPI"

      String.contains?(content, "flask") ->
        "Python/Flask"

      String.contains?(content, "torch") or String.contains?(content, "tensorflow") ->
        "Python/ML (PyTorch/TF)"

      true ->
        "Python"
    end
  end

  defp detect_ruby_project(path) do
    gemfile =
      File.read("#{path}/Gemfile")
      |> then(fn
        {:ok, c} -> c
        _ -> ""
      end)

    if String.contains?(gemfile, "rails"), do: "Ruby on Rails", else: "Ruby"
  end
end
