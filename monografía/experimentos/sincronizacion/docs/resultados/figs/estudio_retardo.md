# Estudio del retardo en el experimento de sincronización

## Aplicación a las 20 frecuencias

| Cantidad | Valor |
|---|---|
| Desintonía máxima (rad/s) | 0.2513 |
| u* (rad/s) | 0.2591 |
| K_c (rad/s) | 0.3350 |
| r en K_c | 0.7735 |
| Cotas de K_c (rad/s) | 0.2513 a 0.5027 |
| N infinito con densidad uniforme (rad/s) | 0.3200 |
| Dos raíces de K f(u) = u hasta K / K_c | 1.0185 |

| K / K_c | Raíz | r | Mayor autovalor no trivial |
|---|---|---|---|
| 1.0001 | mayor | 0.7766 | -0.00441 |
| 1.0001 | menor | 0.7703 | +0.00440 |
| 1.05 | mayor | 0.8453 | -0.10257 |
| 1.2 | mayor | 0.9029 | -0.21663 |
| 1.5 | mayor | 0.9458 | -0.36959 |
| 2 | mayor | 0.9718 | -0.57639 |

## Estado enganchado con retardo uniforme

| h (ms) | tau (ms) | K / K_c | Omega (rad/s) | r | Desfasaje del nodo 20 (rad) |
|---|---|---|---|---|---|
| 500 | 255 | 1.2 | 1.1712 | 0.8787 | 1.0267 |
| 500 | 255 | 1.5 | 1.1372 | 0.9388 | 0.6393 |
| 500 | 255 | 2 | 1.0928 | 0.9691 | 0.4337 |
| 250 | 131 | 1.1 | 1.2162 | 0.8610 | 1.0317 |
| 250 | 131 | 1.5 | 1.1910 | 0.9439 | 0.5870 |

| h (ms) | tau (ms) | Umbral K / K_c | Factor 1 / cos(omega_media tau) |
|---|---|---|---|
| 500 | 255 | 1.174 | 1.054 |
| 250 | 131 | 1.058 | 1.014 |

## Umbral simulado desde el estado enganchado (h = 500 ms, retardo de un paso, 800 s)

| K / K_c | Engancha | Dispersión de frecuencias (rad/s) | r |
|---|---|---|---|
| 1.05 | No | 0.20349 | 0.7081 |
| 1.1 | No | 0.14931 | 0.7822 |
| 1.15 | No | 0.09317 | 0.8315 |
| 1.18 | No | 0.03240 | 0.8524 |
| 1.19 | Sí | 0.00000 | 0.8605 |
| 1.2 | Sí | 0.00000 | 0.8696 |
| 1.25 | Sí | 0.00000 | 0.8910 |

## Esquema cruzado (h = 500 ms, retardo de un paso, 120 s, desde el estado enganchado de 1,5 K_c)

| K / K_c | Semillas | r total | r esquema normal | r esquema cruzado |
|---|---|---|---|---|
| 1.5 | 8 | 0.117 (0.114 a 0.120) | 0.632 (0.618 a 0.645) | 0.669 (0.660 a 0.685) |
| 2.5 | 4 | 0.198 (0.194 a 0.206) | 0.918 (0.916 a 0.920) | 0.921 (0.918 a 0.923) |
| 3 | 4 | 0.232 (0.231 a 0.232) | 0.947 (0.947 a 0.947) | 0.947 (0.947 a 0.947) |
| 4 | 4 | 0.298 (0.291 a 0.303) | 0.969 (0.967 a 0.971) | 0.968 (0.966 a 0.970) |
