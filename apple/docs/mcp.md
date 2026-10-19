# PixPin como servidor MCP en el Mac

El mismo MCP de Windows (`apps/pixpin-mcp`), en `nucleo/pixpin-mcp`, y va
dentro de la app: `/Applications/PixPin.app/Contents/MacOS/pixpin-mcp`.

## Claude Desktop

En `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "pixpin": { "command": "/Applications/PixPin.app/Contents/MacOS/pixpin-mcp" }
  }
}
```

## Claude Code

```sh
claude mcp add pixpin /Applications/PixPin.app/Contents/MacOS/pixpin-mcp
```

## Qué hace

- **Lee aquí mismo**, sin la app: buscar en mis cosas, las tareas, los
  chats y el texto de un PDF (su capa de texto), Word, PowerPoint, Excel,
  EPUB, HTML o Markdown. `ver_pantalla` usa `screencapture` (pide el
  permiso de grabar la pantalla). El OCR de una imagen o un PDF escaneado
  no: en el Mac es Vision, dentro de la app.
- **Escribe en PixPin** (tareas, notas, mensajes, lienzos, documentos…):
  manda el pedido `herramienta` por el enlace `pixpinmax://pedido`, firmado
  con la clave de la app (`enlaces.clave`), y espera la respuesta en un
  fichero temporal. Lo que borra o cambia algo lo pregunta PixPin antes.
