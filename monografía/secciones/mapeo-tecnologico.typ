== Mapeo tecnológico <sec-mapeo-tecnologico>

// Pedido del profesor (mail del 27/10). Aplica a todo el trabajo: ponerle marca y modelo a los equipos reales con los que se
// implementaría el sistema, dónde se comprarían y cuánto cuestan. Es lo primero que se pregunta en un caso real
// (¿cuánto sale hacer esto?).
//
// Escenario de referencia: la telemetría del experimento 1 (@sec-exp-mqtt-https) llevada a hardware real. No se hace un mapeo
// por caso de uso. La sección va después del diseño experimental porque usa sus resultados.
//
// Componentes a relevar:
// - Dispositivos de borde: placas de la familia ESP32, como en los experimentos (reemplazo real de lo emulado con QEMU).
// - Conectividad, de menor a mayor alcance: Wi-Fi existente, módem celular (LTE-M o 4G) con su plan de datos, gateway LoRaWAN
//   con ChirpStack (referenciar @sec-caso-lora).
// - Broker: Mosquitto en un servidor propio (VPS) o un servicio MQTT administrado, con su costo mensual.
// Para cada equipo: modelo, proveedor (local o importación), precio con fecha y moneda, y la fuente.
//
// Usar los bytes por mensaje medidos en el experimento 1 para estimar costos, por ejemplo el consumo mensual de un plan celular
// por dispositivo. Verificar cómo cobra cada broker administrado (algunos cobran por mensaje en bloques de tamaño fijo, y en ese
// caso achicar el payload no reduce el costo).
//
// Justificar las elecciones con los tres factores que acotan un proyecto (calidad técnica, plazo y presupuesto). La idea es
// proponer una solución viable, no necesariamente la de máxima calidad técnica.
//
// TODO(mapeo tecnológico) Definir la escala del escenario (cantidad de nodos y frecuencia de publicación, idealmente las del
// experimento 1).
