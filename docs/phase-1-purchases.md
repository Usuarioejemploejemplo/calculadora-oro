# AU · Diseño técnico y Fase 1: Compras y clientes

## Decisiones confirmadas
- Sistema completo para casa de empeños.
- Varias sucursales.
- Varios empleados con roles.
- Clientes compartidos para compras y empeños.
- Recibo de compra y contrato de empeño (el contrato se implementará en una fase posterior).
- Operación sin conexión como mejora opcional; la primera versión requiere conexión para guardar datos centralizados.

## Arquitectura
- PWA actual como interfaz web instalable.
- Supabase Auth para identidades individuales.
- PostgreSQL para datos relacionales.
- Row Level Security (RLS) para aislar organizaciones y sucursales.
- Supabase Storage privado para fotografías y documentos.
- Funciones backend para numeración de recibos, anulaciones y operaciones financieras.
- Zona horaria de presentación: America/Tegucigalpa; instantes guardados en timestamptz.
- Moneda operativa: HNL.

## Roles iniciales
- owner/admin: acceso a todas las sucursales de la organización.
- Los dos usuarios principales tendrán rol `admin` y permisos idénticos en toda la organización.
- Todos los miembros activos podrán consultar todas las sucursales de la organización mediante la migración `002_shared_access_all_branches.sql`.
- Las cuentas individuales se conservan para identificar quién registró cada operación y mantener auditoría.

La aplicación no debe confiar en controles visuales del frontend: todas las restricciones se aplican también en RLS/backend.

## Modelo de datos de Fase 1
- organizations: negocio propietario de los datos.
- branches: sucursales.
- user_profiles: perfil y rol de cada usuario autenticado.
- branch_memberships: sucursales asignadas a cada empleado.
- customers: registro de clientes compartido dentro de la organización.
- purchases: encabezado de cada compra, con sucursal, empleado, cliente, cotización y descuento congelados.
- purchase_items: una o varias piezas por compra, con peso, quilataje y cálculo.
- purchase_attachments: referencias a fotos/documentos almacenados de forma privada.
- audit_events: bitácora de acciones relevantes.

La migración SQL inicial está en `supabase/migrations/001_phase1_purchases.sql`.

## Flujo de compra
1. Cada administrador inicia sesión con su propia cuenta.
2. Ambos pueden seleccionar y operar en cualquiera de las sucursales de la organización.
3. Busca un cliente existente o registra uno nuevo.
4. La calculadora entrega una cotización y permite añadir una o varias piezas.
5. Se valida peso > 0, quilataje entre 1K y 24K, descuento permitido y total.
6. Antes de confirmar, se muestra un resumen para revisión.
7. El backend asigna el número único de recibo y guarda compra + piezas en una transacción.
8. Se genera el recibo imprimible/PDF y se adjuntan fotografías privadas.
9. La operación queda en historial y en auditoría.

## Reglas contables y de integridad
- Guardar cotización HNL/gramo, descuento, precio unitario y total exactos usados en cada operación.
- Los registros históricos no se recalculan al cambiar el spot.
- Las compras completadas no se borran: se anulan con motivo y registro de auditoría.
- Los totales se calculan y validan en backend; el frontend solo presenta una previsualización.
- No asumir que el peso bruto es peso neto: incluir peso de piedras/elementos no auríferos cuando corresponda.
- La compra puede contener varias piezas; cada pieza conserva su quilataje y peso.
- El número de recibo debe generarse en backend, de forma transaccional y única por sucursal.

## Pantallas de Fase 1
1. Inicio de sesión.
2. Selector de sucursal (solo sucursales autorizadas).
3. Panel inicial con resumen de compras recientes.
4. Clientes: listado, búsqueda, alta y ficha.
5. Nueva compra: cliente, sucursal, piezas, cotización, descuento, fotografías y observaciones.
6. Confirmación y recibo.
7. Historial: filtros por fecha, cliente, sucursal, empleado y estado.
8. Detalle de compra: recibo, piezas, fotos y auditoría visible según rol.

## Criterios de aceptación
- Un empleado solo puede operar en sucursales asignadas.
- Un administrador puede consultar todas las sucursales de su organización.
- No se puede guardar una compra sin cliente, sucursal, empleado, peso y quilataje válidos.
- Una compra conserva la cotización y descuento originales.
- El número de recibo no se duplica, incluso con dos empleados registrando al mismo tiempo.
- Los registros completados no se eliminan físicamente desde la interfaz.
- Un usuario de otra organización no puede leer clientes, compras ni fotos.
- Los importes del recibo coinciden con los valores guardados en base de datos.

## Secuencia de implementación
1. Crear proyecto Supabase y ejecutar migración.
2. Crear la organización y sucursales iniciales.
3. Configurar el primer usuario administrador y perfiles de empleados.
4. Completar las funciones backend para recibos y anulaciones.
5. Conectar la PWA a Supabase mediante variables de configuración públicas (URL y anon/publishable key); nunca incluir service-role key en el navegador.
6. Implementar pantallas de clientes y compras.
7. Configurar bucket privado y políticas de almacenamiento para fotos.
8. Probar con dos usuarios y dos sucursales antes de publicar en producción.

## Alcance de esta entrega
Esta rama incorpora la especificación y el esquema SQL inicial. Todavía no activa escrituras reales ni cambia la PWA publicada. Se requiere configurar Supabase y completar las funciones transaccionales, el almacenamiento privado y las pruebas antes de habilitar compras reales.
