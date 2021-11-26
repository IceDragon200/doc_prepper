defmodule DocPrepper.HTML do
  require EEx

  import Phoenix.HTML

  alias DocPrepper.Document.Namespace

  EEx.function_from_file(:def, :render_namespace, Path.expand("../../priv/templates/namespace.html.eex", __DIR__), [:assigns])
  EEx.function_from_file(:def, :render_namespace_spec, Path.expand("../../priv/templates/_namespace_spec.html.eex", __DIR__), [:assigns])
  EEx.function_from_file(:def, :render_type, Path.expand("../../priv/templates/_type.html.eex", __DIR__), [:assigns])
  EEx.function_from_file(:def, :render_type_spec, Path.expand("../../priv/templates/_type_spec.html.eex", __DIR__), [:assigns])
  EEx.function_from_file(:def, :render_const, Path.expand("../../priv/templates/_const.html.eex", __DIR__), [:assigns])
  EEx.function_from_file(:def, :render_func, Path.expand("../../priv/templates/_func.html.eex", __DIR__), [:assigns])
  EEx.function_from_file(:def, :render_class_spec, Path.expand("../../priv/templates/_class_spec.html.eex", __DIR__), [:assigns])

  def html_escape!(blob) do
    {:safe, blob} = html_escape(blob)
    blob
  end

  def render_document(%Namespace{} = ns) do
  end
end
