import Foundation

/// Embedded strings keep both distributed apps self-contained. No account data is translated.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case portuguese = "pt-BR"
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .portuguese: return "Português"
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }
    var needsAnnouncementTranslation: Bool { self != .english }
    func translationKey(for post: ResetPost) -> String { rawValue + ":" + post.translationRevision }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let translated = self == .portuguese ? key : Self.translations[key]?[self == .english ? 0 : 1] ?? key
        return arguments.isEmpty ? translated : String(format: translated, locale: locale, arguments: arguments)
    }

    func date(_ date: Date, includeDate: Bool = true) -> String {
        date.formatted(Date.FormatStyle(date: includeDate ? .abbreviated : .omitted,
                                       time: includeDate ? .shortened : .standard).locale(locale))
    }

    func error(_ error: Error) -> String {
        if let error = error as? AppLocalizedError { return error.message(in: self) }
        return text("Não foi possível concluir a consulta (código %d).", (error as NSError).code)
    }

    static let translations: [String: [String]] = [
        "Clique na foto para ler o último anúncio de reset.": ["Click the photo to read the latest reset announcement.", "Haz clic en la foto para leer el último anuncio de reinicio."],
        "Resumo do último reset": ["Latest reset summary", "Resumen del último reinicio"],
        "Resumo fornecido pelo site; o link abre a referência no X.": ["Summary provided by the site; the link opens its reference on X.", "Resumen proporcionado por el sitio; el enlace abre su referencia en X."],
        "Referência no X ↗": ["Reference on X ↗", "Referencia en X ↗"],
        "Texto da fonte · inglês": ["Source text · English", "Texto de la fuente · inglés"],
        "Estilo da franquia": ["Quota style", "Estilo de cuota"],
        "Compacto": ["Compact", "Compacto"],
        "Número grande": ["Large number", "Número grande"],
        "A porcentagem cresce ao abrir o painel, dentro do espaço disponível da barra.": ["The percentage grows when the panel opens, within the available menu bar space.", "El porcentaje crece al abrir el panel, dentro del espacio disponible en la barra."],
        "Recentes": ["Recents", "Recientes"],
        "Conversa sem título": ["Untitled chat", "Chat sin título"],
        "Idioma": ["Language", "Idioma"],
        "Configurações — Codex Reset": ["Settings — Codex Reset", "Configuración — Codex Reset"],
        "Monte o seu painel": ["Build your panel", "Diseña tu panel"],
        "Arraste os campos para escolher a posição de cada informação.": ["Drag fields to choose where each item appears.", "Arrastra los campos para elegir dónde aparece cada dato."],
        "Montar painel": ["Panel layout", "Diseño del panel"],
        "Tamanho e opções": ["Size and options", "Tamaño y opciones"],
        "Salvo automaticamente neste Mac.": ["Saved automatically on this Mac.", "Se guarda automáticamente en este Mac."],
        "Ocultar na barra de menus": ["Hide to menu bar", "Ocultar en la barra de menús"],
        "Padrão": ["Default", "Predeterminado"],
        "Só porcentagem": ["Percentage only", "Solo porcentaje"],
        "Agente e tok/s": ["Agent and tok/s", "Agente y tok/s"],
        "Conversa + tok/s": ["Chat + tok/s", "Chat + tok/s"],
        "Arraste os campos para o desenho da tela": ["Drag fields onto the screen preview", "Arrastra los campos a la vista previa de la pantalla"],
        "Testar desenho novo": ["Try new editor", "Probar el nuevo editor"],
        "Editor anterior": ["Previous editor", "Editor anterior"],
        "Ajuste de tamanho": ["Size adjustments", "Ajustes de tamaño"],
        "Ajustar automaticamente": ["Size automatically", "Ajustar automáticamente"],
        "Largura da direita": ["Right side width", "Ancho del lado derecho"],
        "Largura do painel aberto": ["Expanded panel width", "Ancho del panel abierto"],
        "Altura da barra": ["Bar height", "Altura de la barra"],
        "Espaço extra embaixo": ["Extra space below", "Espacio extra debajo"],
        "Ctrl + Option + arrastar no monitor também ajusta o tamanho. No painel aberto, ajusta os detalhes; na barra, ajusta o topo. A altura do topo respeita o espaço da barra de menus da tela.": ["You can also hold Ctrl + Option and drag the monitor to resize it. Drag the expanded panel to resize the details, or the bar to resize the top. The top stays within the screen’s menu bar.", "También puedes mantener Ctrl + Option y arrastrar el monitor para cambiar su tamaño. En el panel abierto se ajustan los detalles; en la barra, la parte superior. La altura se mantiene dentro de la barra de menús de la pantalla."],
        "Porcentagem e barra de franquia no lado esquerdo": ["Percentage and quota bar on the left", "Porcentaje y barra de cuota a la izquierda"],
        "Permitir expandir a lista de outras conversas": ["Allow expanding the list of other chats", "Permitir desplegar la lista de otros chats"],
        "Nome curto do modelo (ex.: 6.1 Sol)": ["Short model name (e.g. 6.1 Sol)", "Nombre corto del modelo (p. ej., 6.1 Sol)"],
        "Destacar novo reset nas três primeiras aberturas": ["Highlight a new reset the first three times the panel opens", "Destacar un nuevo reinicio las tres primeras veces que se abra el panel"],
        "Total processado/s soma entrada e saída, incluindo o contexto em cache. Saída/s mostra só a saída. São médias entre registros do Codex, não velocidade instantânea nem franquia debitada; sem amostras recentes, mostram um traço. O agente principal é o de maior esforço entre as conversas ativas.": ["Total processed/s adds input and output, including cached context. Output/s shows output only. These are averages between Codex records, not instantaneous speed or quota charged; without recent samples, a dash appears. The main agent is the one with the highest effort among active chats.", "Total procesado/s suma entrada y salida, incluido el contexto en caché. Salida/s muestra solo la salida. Son promedios entre registros de Codex, no velocidad instantánea ni cuota consumida; sin muestras recientes, aparece una raya. El agente principal es el de mayor esfuerzo entre los chats activos."],
        "Informações disponíveis": ["Available information", "Información disponible"],
        "Arraste uma peça": ["Drag an item", "Arrastra un elemento"],
        "ESQUERDA": ["LEFT", "IZQUIERDA"],
        "CÂMERA FIXA": ["FIXED CAMERA", "CÁMARA FIJA"],
        "DIREITA · DUAS LINHAS": ["RIGHT · TWO ROWS", "DERECHA · DOS FILAS"],
        "Câmera do Mac": ["Mac camera", "Cámara del Mac"],
        "PAINEL ABERTO · TRÊS LINHAS": ["EXPANDED PANEL · THREE ROWS", "PANEL ABIERTO · TRES FILAS"],
        "À esquerda fica a franquia. No meio, a câmera. À direita, as informações que você montar. A parte de baixo aparece quando o painel abre.": ["Quota is on the left, the camera in the middle, and your chosen information on the right. The lower section appears when the panel opens.", "La cuota está a la izquierda, la cámara en el centro y la información que elijas a la derecha. La parte inferior aparece al abrir el panel."],
        "Mova as peças para mudar a ordem, use × para remover e + para adicionar sem arrastar. Em telas sem notch, as linhas de cima ficam em uma linha na barra de menus.": ["Move items to reorder them, use × to remove and + to add without dragging. On screens without a notch, the top rows share one line in the menu bar.", "Mueve los elementos para cambiar el orden, usa × para quitar y + para añadir sin arrastrar. En pantallas sin notch, las filas superiores se reúnen en una línea en la barra de menús."],
        "Campos": ["Fields", "Campos"],
        "Arraste para o desenho": ["Drag onto the preview", "Arrastra a la vista previa"],
        "Seu notch": ["Your notch", "Tu notch"],
        "câmera": ["camera", "cámara"],
        "Cada área é uma linha. Arraste os campos já colocados para reorganizar; use × para remover. O menu + também adiciona campos.": ["Each area is a row. Drag placed fields to reorder them; use × to remove. The + menu also adds fields.", "Cada área es una fila. Arrastra los campos colocados para reorganizarlos; usa × para quitar. El menú + también permite añadir campos."],
        "Em telas sem notch, as linhas de cima são reunidas na barra de menus.": ["On screens without a notch, the top rows are combined in the menu bar.", "En pantallas sin notch, las filas superiores se reúnen en la barra de menús."],
        "Arraste campos para esta linha": ["Drag fields onto this row", "Arrastra campos a esta fila"],
        "Remover %@ da linha %d": ["Remove %@ from row %d", "Quitar %@ de la fila %d"],
        "Adicionar campo à linha %d de cima": ["Add a field to top row %d", "Añadir un campo a la fila superior %d"],
        "Adicionar campo à linha %d de baixo": ["Add a field to detail row %d", "Añadir un campo a la fila inferior %d"],
        "Conversa": ["Chat", "Chat"],
        "Projeto": ["Project", "Proyecto"],
        "Total processado/s": ["Total processed/s", "Total procesado/s"],
        "Saída/s": ["Output/s", "Salida/s"],
        "Modelo / agente": ["Model / agent", "Modelo / agente"],
        "Esforço": ["Effort", "Esfuerzo"],
        "Conversas ativas": ["Active chats", "Chats activos"],
        "Franquia restante": ["Remaining quota", "Cuota restante"],
        "Reset extra": ["Extra reset", "Reinicio extra"],
        "Reset de 5 horas": ["5-hour reset", "Reinicio de 5 horas"],
        "Não informado pelo Codex": ["Not reported by Codex", "No informado por Codex"],
        "Reset semanal": ["Weekly reset", "Reinicio semanal"],
        "Último reset": ["Last reset", "Último reinicio"],
        "Anúncio do Tibo": ["Tibo’s announcement", "Anuncio de Tibo"],
        "%d ativa": ["%d active", "%d activo"],
        "%d ativas": ["%d active", "%d activos"],
        "Buscando previsão…": ["Loading forecast…", "Buscando previsión…"],
        "Previsão indisponível": ["Forecast unavailable", "Previsión no disponible"],
        "Em %@": ["In %@", "En %@"],
        "Aguardando atualização": ["Waiting for an update", "Esperando actualización"],
        "Ainda não observado": ["Not observed yet", "Aún no observado"],
        "Somente tokens de saída, incluindo raciocínio. Média entre atualizações, não velocidade instantânea.": ["Output tokens only, including reasoning. Average between updates, not instantaneous speed.", "Solo tokens de salida, incluido el razonamiento. Promedio entre actualizaciones, no velocidad instantánea."],
        "Entrada + saída, incluindo contexto em cache. Não equivale à franquia debitada nem à velocidade de geração.": ["Input + output, including cached context. This is not quota charged or generation speed.", "Entrada + salida, incluido el contexto en caché. No equivale a cuota consumida ni a velocidad de generación."],
        " O Codex ainda não informou duas amostras recentes.": [" Codex has not reported two recent samples yet.", " Codex aún no ha informado de dos muestras recientes."],
        " Amostra de %@": [" Sample from %@", " Muestra de %@"],
        ". Cache incluído: %@": [". Included cache: %@", ". Caché incluida: %@"],
        "Novo reset ainda não visto": ["New reset not yet seen", "Nuevo reinicio aún no visto"],
        "Franquia semanal do Codex: %@ restante": ["Codex weekly quota: %@ remaining", "Cuota semanal de Codex: %@ restante"],
        "Ocultar outras conversas": ["Hide other chats", "Ocultar otros chats"],
        "Mostrar outras conversas": ["Show other chats", "Mostrar otros chats"],
        "OUTRAS CONVERSAS · %d": ["OTHER CHATS · %d", "OTROS CHATS · %d"],
        "Abrir configurações": ["Open settings", "Abrir configuración"],
        "Configurações do Codex Reset": ["Codex Reset settings", "Configuración de Codex Reset"],
        "Fechar Codex Reset": ["Quit Codex Reset", "Salir de Codex Reset"],
        "Novo reset": ["New reset", "Nuevo reinicio"],
        "Franquia renovada em %@": ["Quota renewed on %@", "Cuota renovada el %@"],
        "Aguardando dados da conta": ["Waiting for account data", "Esperando datos de la cuenta"],
        "Sem atividade": ["No activity", "Sin actividad"],
        "Entrada + saída · cache incluído": ["Input + output · cache included", "Entrada + salida · caché incluida"],
        "Média de saída": ["Average output", "Promedio de salida"],
        "Informado pelo Codex": ["Reported by Codex", "Informado por Codex"],
        "Atualizando previsão": ["Updating forecast", "Actualizando previsión"],
        "Atualizar previsão do reset extra": ["Refresh extra reset forecast", "Actualizar previsión del reinicio extra"],
        "Falha na última consulta: %@ Clique para tentar novamente.": ["Last request failed: %@ Click to retry.", "Falló la última consulta: %@ Haz clic para reintentar."],
        "Consultar agora a previsão do reset extra": ["Check the extra reset forecast now", "Consultar ahora la previsión del reinicio extra"],
        "Histórico em atualização": ["Updating history", "Actualizando historial"],
        "Fonte indisponível": ["Source unavailable", "Fuente no disponible"],
        "Horário ainda indisponível": ["Time not available yet", "Horario aún no disponible"],
        "Janela encerrada": ["Window ended", "Ventana finalizada"],
        "Aguardando novos dados": ["Waiting for new data", "Esperando nuevos datos"],
        "Dentro da janela\nAté %@": ["Within the window\nUp to %@", "Dentro de la ventana\nHasta %@"],
        "Estimativa · poucos dados": ["Estimate · limited data", "Estimación · pocos datos"],
        "Dentro da janela": ["Within the window", "Dentro de la ventana"],
        "Estimativa: até %@": ["Estimate: up to %@", "Estimación: hasta %@"],
        "Entre %@\ne %@": ["Between %@\nand %@", "Entre %@\ny %@"],
        "Estimativa histórica": ["Historical estimate", "Estimación histórica"],
        "Anúncio verificado na fonte": ["Announcement verified at source", "Anuncio verificado en la fuente"],
        "Horário anunciado passou": ["Announced time has passed", "El horario anunciado ya pasó"],
        "Aguardando confirmação": ["Awaiting confirmation", "Esperando confirmación"],
        "Reset extra anunciado": ["Extra reset announced", "Reinicio extra anunciado"],
        "Sem estimativa": ["No estimate", "Sin estimación"],
        "Histórico insuficiente": ["Insufficient history", "Historial insuficiente"],
        "agora": ["just now", "ahora"],
        "há %@": ["%@ ago", "hace %@"],
        "X-high": ["X-high", "Extra alto"],
        "Ultra": ["Ultra", "Ultra"],
        "Max": ["Max", "Máximo"],
        "High": ["High", "Alto"],
        "Medium": ["Medium", "Medio"],
        "Low": ["Low", "Bajo"],
        "Ler último anúncio de reset do Tibo": ["Read Tibo’s latest reset announcement", "Leer el último anuncio de reinicio de Tibo"],
        "Último anúncio de reset · traduzido para português": ["Latest reset announcement · English original", "Último anuncio de reinicio · traducido al español"],
        "Último anúncio de reset": ["Latest reset announcement", "Último anuncio de reinicio"],
        "A tradução integrada requer macOS 15 ou posterior.": ["Built-in translation requires macOS 15 or later.", "La traducción integrada requiere macOS 15 o posterior."],
        "Link %d ↗": ["Link %d ↗", "Enlace %d ↗"],
        "Anúncio original ↗": ["Original announcement ↗", "Anuncio original ↗"],
        "Buscando o anúncio…": ["Loading announcement…", "Buscando el anuncio…"],
        "Anúncio ainda indisponível.": ["Announcement not available yet.", "Anuncio aún no disponible."],
        "Atualizar": ["Refresh", "Actualizar"],
        "Tradução automática · português": ["Original · English", "Traducción automática · español"],
        "Tentar traduzir": ["Retry translation", "Reintentar traducción"],
        "Traduzindo para português…": ["Loading original…", "Traduciendo al español…"],
        "Não foi possível traduzir agora. Confira os idiomas de tradução deste Mac.": ["Translation is unavailable right now. Check this Mac’s translation languages.", "No se ha podido traducir. Comprueba los idiomas de traducción de este Mac."],
        "A fonte de resets retornou dados inválidos.": ["The reset source returned invalid data.", "La fuente de reinicios devolvió datos no válidos."],
        "A fonte de resets está indisponível (HTTP %d).": ["The reset source is unavailable (HTTP %d).", "La fuente de reinicios no está disponible (HTTP %d)."],
        "Ainda não há resets extraordinários observados para calcular a estimativa.": ["No extra resets have been observed yet to calculate an estimate.", "Aún no se han observado reinicios extraordinarios para calcular una estimación."],
        "Não encontrei o executável do Codex neste Mac.": ["The Codex executable was not found on this Mac.", "No se ha encontrado el ejecutable de Codex en este Mac."],
        "A conexão com o Codex foi encerrada.": ["The connection to Codex was closed.", "Se ha cerrado la conexión con Codex."],
        "O Codex demorou demais para responder: %@.": ["Codex took too long to respond: %@.", "Codex tardó demasiado en responder: %@."],
        "O Codex retornou dados incompletos: %@.": ["Codex returned incomplete data: %@.", "Codex devolvió datos incompletos: %@."],
        "Erro do Codex.": ["Codex error.", "Error de Codex."],
        "Não encontrei o histórico local do Codex neste Mac.": ["Local Codex history was not found on this Mac.", "No se ha encontrado el historial local de Codex en este Mac."],
        "Não foi possível ler as conversas ativas do Codex.": ["Could not read active Codex chats.", "No se han podido leer los chats activos de Codex."],
        "Não foi possível concluir a consulta (código %d).": ["Could not complete the request (code %d).", "No se ha podido completar la consulta (código %d)."],
    ]
}

protocol AppLocalizedError: LocalizedError {
    func message(in language: AppLanguage) -> String
}
extension AppLocalizedError {
    var errorDescription: String? { message(in: .portuguese) }
}
