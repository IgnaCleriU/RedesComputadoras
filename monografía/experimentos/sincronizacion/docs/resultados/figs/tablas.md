# Tablas del experimento de sincronización

## Modelo

| K/K_c | r emulación | r simulación (media de 5) | r teoría | Engancha |
|---|---|---|---|---|
| 0.8 | 0.1608 | 0.1275 | - | 0 |
| 1.2 | 0.87233 | 0.8655 | 0.90287 | 1 |
| 1.5 | 0.93708 | 0.9360 | 0.9458 | 1 |
| 2 | 0.96837 | 0.9680 | 0.97184 | 1 |

## Tráfico

| Corrida | N | QoS | Alias | Total B/s | Subida B/s·nodo | Bajada B/s·nodo | PUBLISH bajada B | Tópico | Protobuf B | Retrans. | Edad p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| alias_k1.5_sin-netem_s1 | 20 | 0 | 1 | 91029.6 | 1283.0 | 3268.5 | 31 | 0 | 23 | 0 | 6.0 | 10.5 | 11.6 |
| calibracion_k1.5_sin-netem_s1 | 20 | 0 | 0 | 100812.3 | 1273.6 | 3767.0 | 45 | 17 | 23 | 0 | 5.0 | 10.1 | 11.0 |
| escala_n10_k1.5_sin-netem_s1 | 10 | 0 | 0 | 25555.2 | 735.5 | 1820.0 | 44 | 16 | 23 | 0 | 3.7 | 10.4 | 10.5 |
| escala_n5_k1.5_sin-netem_s1 | 5 | 0 | 0 | 6687.2 | 461.7 | 875.8 | 44 | 16 | 23 | 0 | 2.3 | 10.5 | 10.8 |
| qos0_perdida_k1.5_perdida-5_s1 | 20 | 0 | 0 | 101494.7 | 1154.1 | 3920.6 | 45 | 17 | 23 | 3041 | 8.6 | 1230.8 | 3267.1 |
| qos1_perdida_k1.5_perdida-5_s1 | 20 | 1 | 0 | 87959.8 | 1099.8 | 3298.2 | 47 | 17 | 23 | 3422 | 13385.0 | 29202.6 | 36002.0 |

## Validez

| Corrida | Nodos | Overruns | Paso UART mediano s | Paso máximo s |
|---|---|---|---|---|
| alias_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.502 |
| broker_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.504 |
| calibracion_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| cruzado_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| escala_n10_k1.5_sin-netem_s1 | 10 | 0 | 0.5 | 0.5 |
| escala_n5_k1.5_sin-netem_s1 | 5 | 0 | 0.5 | 0.501 |
| iguales_v2_k0.4_sin-netem_s1 | 20 | 4 | 0.5 | 0.51 |
| keepalive_con_voluntad_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.508 |
| keepalive_sin_voluntad_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| modelo_k0.8_sin-netem_s1 | 20 | 0 | 0.5 | 0.504 |
| modelo_k1.2_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| modelo_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| modelo_k2_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| qos0_perdida_k1.5_perdida-5_s1 | 20 | 0 | 0.5 | 0.502 |
| qos1_perdida_k1.5_perdida-5_s1 | 20 | 0 | 0.5 | 0.504 |
| union_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.502 |
