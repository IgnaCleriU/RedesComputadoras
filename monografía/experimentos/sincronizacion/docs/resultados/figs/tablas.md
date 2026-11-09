# Tablas del experimento de sincronización

## Modelo

| K/K_c | r emulación | r simulación (media de 5) | r teoría | Engancha |
|---|---|---|---|---|
| 0.8 | 0.1608 | 0.1275 | - | 0 |
| 1.05 | 0.74189 | 0.7154 | 0.84528 | 0 |
| 1.1 | 0.79554 | - | 0.87152 | 0 |
| 1.15 | 0.84311 | - | 0.8894 | 0 |
| 1.2 | 0.87233 | 0.8655 | 0.90287 | 1 |
| 1.25 | 0.89227 | - | 0.91356 | 1 |
| 1.5 | 0.93708 | 0.9360 | 0.9458 | 1 |
| 2 | 0.96837 | 0.9680 | 0.97184 | 1 |

## Tráfico

| Corrida | N | QoS | Alias | Total B/s | Subida B/s·nodo | Bajada B/s·nodo | PUBLISH bajada B | Tópico | Protobuf B | Retrans. | Edad p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| alias_k1.5_sin-netem_s1 | 20 | 0 | 1 | 91029.6 | 1283.0 | 3268.5 | 31 | 0 | 23 | 0 | 6.0 | 10.5 | 11.6 |
| calibracion_k1.5_sin-netem_s1 | 20 | 0 | 0 | 100812.3 | 1273.6 | 3767.0 | 45 | 17 | 23 | 0 | 5.0 | 10.1 | 11.0 |
| escala_n10_k1.5_sin-netem_s1 | 10 | 0 | 0 | 25555.2 | 735.5 | 1820.0 | 44 | 16 | 23 | 0 | 3.7 | 10.4 | 10.5 |
| escala_n5_k1.5_sin-netem_s1 | 5 | 0 | 0 | 6687.2 | 461.7 | 875.8 | 44 | 16 | 23 | 0 | 2.3 | 10.5 | 10.8 |
| keepalive_captura_k1.5_sin-netem_s1 | 20 | 0 | 0 | 99514.1 | 1287.2 | 3688.5 | 45 | 17 | 23 | 4 | 3.3 | 9.1 | 10.1 |
| qos0_perdida_k1.5_perdida-5_s1 | 20 | 0 | 0 | 101494.7 | 1154.1 | 3920.6 | 45 | 17 | 23 | 3041 | 8.6 | 1230.8 | 3267.1 |
| qos0_rep_k1.5_perdida-5_s2 | 20 | 0 | 0 | 101802.0 | 1161.8 | 3928.3 | 45 | 17 | 23 | 3085 | 8.4 | 1080.7 | 2008.1 |
| qos0_rep_k1.5_perdida-5_s3 | 20 | 0 | 0 | 101912.7 | 1167.3 | 3928.3 | 45 | 17 | 23 | 3063 | 8.4 | 1142.3 | 1835.9 |
| qos1_perdida_k1.5_perdida-5_s1 | 20 | 1 | 0 | 87959.8 | 1099.8 | 3298.2 | 47 | 17 | 23 | 3422 | 13385.0 | 29202.6 | 36002.0 |
| qos1_rep_k1.5_perdida-5_s2 | 20 | 1 | 0 | 86368.7 | 1090.4 | 3228.1 | 47 | 17 | 23 | 3397 | 13148.0 | 30552.7 | 35902.3 |
| qos1_rep_k1.5_perdida-5_s3 | 20 | 1 | 0 | 88187.2 | 1107.7 | 3301.7 | 47 | 17 | 23 | 3447 | 12532.2 | 28984.1 | 35106.6 |
| qos1_sin_perdida_k1.5_sin-netem_s1 | 20 | 1 | 0 | 164176.9 | 2907.2 | 5301.6 | 47 | 17 | 23 | 0 | 21.7 | 46.9 | 51.7 |

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
| keepalive_captura_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| keepalive_con_voluntad_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.508 |
| keepalive_sin_voluntad_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| modelo_k0.8_sin-netem_s1 | 20 | 0 | 0.5 | 0.504 |
| modelo_k1.2_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| modelo_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| modelo_k2_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| periodo_250_k1.1_sin-netem_s1 | 20 | 0 | 0.25 | 0.255 |
| periodo_250_k1.5_sin-netem_s1 | 20 | 0 | 0.25 | 0.256 |
| qos0_perdida_k1.5_perdida-5_s1 | 20 | 0 | 0.5 | 0.502 |
| qos0_rep_k1.5_perdida-5_s2 | 20 | 0 | 0.5 | 0.508 |
| qos0_rep_k1.5_perdida-5_s3 | 20 | 0 | 0.5 | 0.502 |
| qos1_perdida_k1.5_perdida-5_s1 | 20 | 0 | 0.5 | 0.504 |
| qos1_rep_k1.5_perdida-5_s2 | 20 | 0 | 0.5 | 0.501 |
| qos1_rep_k1.5_perdida-5_s3 | 20 | 0 | 0.5 | 0.501 |
| qos1_sin_perdida_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| umbral_k1.05_sin-netem_s1 | 20 | 0 | 0.5 | 0.504 |
| umbral_k1.15_sin-netem_s1 | 20 | 0 | 0.5 | 0.503 |
| umbral_k1.1_sin-netem_s1 | 20 | 0 | 0.5 | 0.506 |
| umbral_k1.25_sin-netem_s1 | 20 | 0 | 0.5 | 0.502 |
| union_k1.5_sin-netem_s1 | 20 | 0 | 0.5 | 0.502 |
