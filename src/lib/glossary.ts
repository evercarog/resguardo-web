// «¿Qué significa?»: explicaciones cortas de cada estado, cifra y
// comprobación, con qué hacer. Mismos textos que la app de escritorio
// (src/lib/glossary.ts del repositorio de la app), adaptados a la web: lo que
// allí es un botón aquí se hace «en Resguardo, en ese equipo». Es la única
// fuente: la usan los «?» (InfoTip) y la página «Qué significa cada cosa».

export interface GlossaryEntry {
	title: string;
	/** Qué es, en una o dos frases. */
	text: string;
	/** Qué hacer (si hay algo que hacer). */
	todo?: string;
	group: 'conceptos' | 'cifras' | 'estados' | 'proteccion' | 'web';
}

export const GLOSSARY_GROUPS: Record<GlossaryEntry['group'], string> = {
	conceptos: 'Conceptos',
	estados: 'Estado de un repositorio',
	cifras: 'Cifras',
	proteccion: 'Salud de la protección',
	web: 'En esta web'
};

/** Dónde se arreglan las cosas: la web solo mira (salvo «Copiar ahora»). */
const EN_EQUIPO = 'en Resguardo, en ese equipo';

export const GLOSSARY: Record<string, GlossaryEntry> = {
	// ---------- Conceptos ----------
	destino: {
		group: 'conceptos',
		title: 'Destino',
		text: 'El lugar donde se guardan las copias: un disco o una carpeta de la red, un servidor o un bucket de la nube con su clave. Dentro puede tener varios repositorios.'
	},
	repositorio: {
		group: 'conceptos',
		title: 'Repositorio',
		text: 'Una caja cifrada dentro de un destino, con su propia contraseña. Ahí se guardan las versiones de una o varias copias; sin su contraseña nadie puede abrirla, ni el dueño del disco o de la nube.',
		todo: 'Guarda su contraseña en el kit de recuperación.'
	},
	copia: {
		group: 'conceptos',
		title: 'Copia',
		text: 'Qué carpetas se guardan, en qué repositorio y cuándo. Cada vez que se hace y encuentra cambios, guarda una versión nueva.'
	},
	version: {
		group: 'conceptos',
		title: 'Versión',
		text: 'Una foto completa de tus carpetas en un momento dado, que se puede explorar y restaurar desde la app.'
	},
	'copia-externa': {
		group: 'conceptos',
		title: 'Copia externa (la nube)',
		text: 'Una segunda copia de las versiones fuera de este sitio, en la nube u otro disco, por si hay un robo, un incendio o un ransomware.'
	},
	'sin-cambios': {
		group: 'conceptos',
		title: 'Sin cambios',
		text: 'La copia se hizo a su hora, pero no había nada nuevo, así que no hizo falta guardar otra versión («Solo guardar si hay cambios»). Cuenta como al día.'
	},
	'cambio-inusual': {
		group: 'conceptos',
		title: 'Cambio inusual',
		text: 'Una copia cambió muchísimo más de lo normal, como pasaría si un ransomware cifrara los archivos. Por si acaso, el equipo frena la subida a la nube hasta que alguien lo revise.',
		todo: `Revisa ${EN_EQUIPO} qué cambió antes de confirmar la subida. Si sospechas un ransomware, aísla ese servidor: las versiones anteriores siguen intactas.`
	},

	// ---------- Estado de un repositorio ----------
	'estado-ok': { group: 'estados', title: 'Al día', text: 'Sus copias llegan al ritmo esperado.' },
	'estado-late': {
		group: 'estados',
		title: 'Con retraso',
		text: 'La última versión es algo más antigua de lo habitual para este repositorio. Suele pasar si el equipo estuvo apagado o el repositorio desconectado.',
		todo: 'Comprueba que el equipo esté encendido; si sigue, pide una copia con «Copiar ahora» o mírala ' + EN_EQUIPO + '.'
	},
	'estado-overdue': {
		group: 'estados',
		title: 'Atrasada',
		text: 'Lleva más del doble de lo habitual sin versiones nuevas.',
		todo: `Mira la «Historia» del repositorio: puede que el disco esté desconectado o que una copia falle. Arréglalo ${EN_EQUIPO}.`
	},
	'estado-failed': {
		group: 'estados',
		title: 'Falló',
		text: 'La última copia no se pudo hacer, así que no se guardó ninguna versión.',
		todo: `El mensaje de la copia dice por qué (disco desconectado, servidor que no responde…). Arréglalo ${EN_EQUIPO} y vuelve a copiar.`
	},
	'estado-empty': {
		group: 'estados',
		title: 'Sin copias',
		text: 'Aún no se ha guardado ninguna versión aquí.',
		todo: `Crea una copia que se guarde aquí ${EN_EQUIPO} y haz la primera.`
	},
	'estado-paused': {
		group: 'estados',
		title: 'En pausa',
		text: 'Sus copias automáticas están en pausa a propósito: mientras tanto no se avisa de retrasos.',
		todo: `Se reanudan solas a la hora indicada, o ${EN_EQUIPO}.`
	},
	'estado-held': {
		group: 'estados',
		title: 'Cambio inusual',
		text: 'Una copia cambió mucho más de lo normal y la subida a la nube está frenada hasta que alguien lo revise.',
		todo: `Revísalo ${EN_EQUIPO}. Si sospechas un ransomware, aísla ese servidor.`
	},

	// ---------- Cifras ----------
	'ultima-version': {
		group: 'cifras',
		title: 'Última versión',
		text: 'Cuándo se guardó la versión más reciente. Si después hubo copias sin cambios, también se indica: estaba al día.',
		todo: 'Si es más antigua de lo esperado, mira la «Historia» del repositorio.'
	},
	'ultima-revision': {
		group: 'cifras',
		title: 'Última revisión',
		text: 'La copia se hizo a su hora, pero no había nada nuevo, así que no hizo falta guardar otra versión («Solo guardar si hay cambios»).'
	},
	proxima: {
		group: 'cifras',
		title: 'Próxima',
		text: 'Cuándo toca la siguiente copia automática según su horario, en hora de Colombia. «—»: no tiene horario o no se puede saber.'
	},
	versiones: {
		group: 'cifras',
		title: 'Versiones',
		text: 'Cada copia que encuentra cambios guarda una versión: una foto completa de tus carpetas en ese momento, que se puede explorar y restaurar.',
		todo: 'La retención decide cuántas versiones antiguas se conservan.'
	},
	'tamano-protegido': {
		group: 'cifras',
		title: 'Tamaño protegido',
		text: 'Lo que ocupan tus archivos en la última versión, tal como están en el equipo. No es lo que ocupa el repositorio: gracias a la deduplicación y la compresión suele ocupar mucho menos.'
	},
	'total-protegido': {
		group: 'cifras',
		title: 'Protegidos',
		text: 'La suma del tamaño protegido de todos tus repositorios (lo que ocupan tus archivos en su última versión).'
	},
	'duracion-media': {
		group: 'cifras',
		title: 'Duración media',
		text: 'Cuánto tardan de media las copias de este repositorio, y cuántos datos nuevos guarda cada versión.'
	},
	'dias-actividad': {
		group: 'cifras',
		title: 'Cuadros de actividad',
		text: 'Un cuadro por día, el más reciente a la derecha. Verde: se guardó una versión; verde claro: se hizo la copia sin cambios; ámbar: con avisos; rojo: falló; gris: no hubo copia.'
	},

	// ---------- Salud de la protección ----------
	'prot-copias': {
		group: 'proteccion',
		title: 'Copias automáticas',
		text: 'Que las copias se hagan solas a su hora, aunque nadie se acuerde y la app esté cerrada.',
		todo: `Pon horario a sus copias ${EN_EQUIPO}.`
	},
	'prot-borrado': {
		group: 'proteccion',
		title: 'Protegida contra borrado',
		text: 'Que nadie, ni un ransomware con acceso al equipo, pueda borrar las versiones: un servidor REST de solo añadir o un bucket con bloqueo de objetos. Un disco normal se puede borrar.',
		todo: 'Usa un servidor de solo añadir o una copia externa a un bucket con bloqueo de objetos.'
	},
	'prot-externa': {
		group: 'proteccion',
		title: 'Copia externa',
		text: 'Otra copia fuera de este sitio (la nube u otro disco), por si hay un robo, un incendio o un ransomware.',
		todo: `Configúrala en «Mantenimiento» del repositorio, ${EN_EQUIPO}.`
	},
	'prot-verificacion': {
		group: 'proteccion',
		title: 'Verificación',
		text: 'Comprueba con regularidad que lo guardado no se ha dañado en el disco o en el servidor.',
		todo: `Prográmala en «Mantenimiento», ${EN_EQUIPO}: la rotativa lee todos los datos poco a poco.`
	},
	'prot-restauracion': {
		group: 'proteccion',
		title: 'Prueba de restauración',
		text: 'Restaura unos archivos al azar y comprueba que salen enteros: así sabes que las copias se pueden recuperar, no solo que existen.',
		todo: `Prográmala en «Mantenimiento», ${EN_EQUIPO}.`
	},
	'prot-kit': {
		group: 'proteccion',
		title: 'Kit de recuperación',
		text: 'Una hoja con lo necesario para abrir tus copias desde otro equipo si pierdes este (la ubicación y la contraseña).',
		todo: `Prepáralo ${EN_EQUIPO}, imprímelo o guárdalo fuera del equipo y confírmalo.`
	},
	'prot-retencion': {
		group: 'proteccion',
		title: 'Retención',
		text: 'Cuántas versiones antiguas se conservan. Sin ella, el repositorio crece sin fin.',
		todo: `Elige un ajuste rápido en «Retención», ${EN_EQUIPO}.`
	},

	// ---------- En esta web ----------
	'equipo-conexion': {
		group: 'web',
		title: 'Conectado / sin conexión',
		text: 'Cada equipo envía su estado cada pocos minutos. Si pasa media hora sin noticias, aparece «Sin conexión»: puede estar apagado, sin internet o con Resguardo cerrado.'
	},
	'copias-a-distancia': {
		group: 'web',
		title: 'Copiar ahora (a distancia)',
		text: 'Pide al equipo que haga ya una copia que tiene configurada. Solo eso: desde aquí no se puede restaurar, borrar ni cambiar nada. Cada equipo tiene que permitirlo.',
		todo: `Para usarlo, activa «Copias a distancia» ${EN_EQUIPO}.`
	},
	'servidor-copias': {
		group: 'conceptos',
		title: 'Servidor de copias',
		text: 'Un equipo tuyo que guarda las copias de tus otros equipos, como un servidor REST de solo añadir: cada equipo solo ve su carpeta y no puede borrar nada. Va cifrado (TLS) y cada equipo entra con su propia clave, que se entrega cifrada.',
		todo: `Se activa en Resguardo, en ese equipo (Ajustes › Este equipo › «Servidor de copias»). Para usarlo desde otra sede hay que abrir un puerto en el router: Resguardo nunca lo abre solo.`
	},
	'equipo-gestionado': {
		group: 'conceptos',
		title: 'Equipo gestionado',
		text: 'Un PC con «Resguardo Agente»: no tiene la app completa y lo administra otro equipo tuyo, la consola, que le manda la configuración firmada y cifrada. La web solo la transporta y muestra su estado: no puede darle órdenes.',
		todo: `Las copias se cambian o se piden desde la consola. Si ves «Servicio detenido por un administrador», alguien paró Resguardo en ese PC: lo ya copiado sigue a salvo.`
	},
	avisos: {
		group: 'web',
		title: 'Avisos',
		text: 'Notificaciones en el celular o el computador cuando una copia falla o se atrasa, un equipo deja de conectarse o hay un cambio inusual, y cuando se recupera. Los lunes llega un resumen de la semana.'
	}
};

/** Clave del glosario para cada nivel de estado. */
export const LEVEL_TERM = {
	ok: 'estado-ok',
	late: 'estado-late',
	overdue: 'estado-overdue',
	failed: 'estado-failed',
	empty: 'estado-empty',
	paused: 'estado-paused',
	held: 'estado-held'
} as const;
