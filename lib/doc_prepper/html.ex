defmodule DocPrepper.HTML do
  require EEx

  import Phoenix.HTML

  alias DocPrepper.Document.Namespace

  EEx.function_from_file(:def, :render_namespace, Path.expand("../../priv/templates/namespace.html.eex", __DIR__), [:assigns])

  def html_escape!(blob) do
    {:safe, blob} = html_escape(blob)
    blob
  end

  def render_document(%Namespace{} = ns) do
  end
end
