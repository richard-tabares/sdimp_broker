# Por hacer
- [] Corregir `Direccion` en `data/conf.txt`: el endpoint responde 404 "Mina no encontrada" para 192.168.0.100. Verificar `tbl_mina.IP` y los dispositivos 1..N antes de la prueba de 15 equipos.
- [] Revisar en que orden de variables llega la trama desde el equipo

# En progreso



# Finalizadas
- [x] desacoplar el envio HTTP del broker: cola acotada, workers persistentes particionados por equipo, descarte de la trama mas vieja y resumen HTTP
- [x] ajustar el simulador al comportamiento real del equipo: cadencia de 2 s, sin espera de ACK, conteo de ACKs, random walk y formato de trama configurable
- [x] verificar que si no estan llegando tramas del los diferentes equipos, el indincar del circulo de cada estacion debe pasar a rojo, actualmente se queda en verde, pero cuando el equipo deja de transmitir nunca se cambia
- [x] agregar pie de pagina para agregar sitio web y logo de SDIMP esta en /data/logo.png y el sitio web es www.sdimp.com
- [x] dar mas padding horizontal a los recuadros de los titulos de las estaciones, que sea consistente para todas las cantidades que salgan
- [x] quitar graficos circulares del visor para todos lo equipo, pero no borrar el codigo, solo comentalo
- [x] los datos de los sensore deben mostrar su respectiva unidad de medida
- [x] revisar tamaños de textos del titulo de los equipos (ej: Estacion 01, Estacion 02 etc) sean consistente, cuando tengo 15 equipos o estaciones configurada, se ve muy bien, pero cuando tengo el texto se pone mas grande y se sale del recuadro; adaptar el circulo de conexion al tamaño del recuadro; mantener el tamaño de fila estandar de cinco equipos; y aumentar un poco el texto de las filas
- [x] no hacer las filas con bordes redondeados
- [x] texto de los encabezados en negrito un poco mas grandes y su linea bottom de fila del mismo color de las filas de contenido