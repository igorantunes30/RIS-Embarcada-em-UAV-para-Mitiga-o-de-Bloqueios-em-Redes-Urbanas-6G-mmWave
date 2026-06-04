# inteiro — Comparação de Cenários RIS com Algoritmo Genético

Resultados da comparação entre cinco cenários de comunicação sem fio em ambiente indoor, gerados pelo simulador SimRIS. O script `plot_comparacao.m` carrega os dados, calcula estatísticas e gera três gráficos de análise.

---

## Cenário Simulado

Ambiente **outdoor (UMi — Urban Microcell)** a **28 GHz**, com layout de nós e obstáculos definidos em `cenarioS.csv`.

| Parâmetro | Valor |
|-----------|-------|
| Modelo de propagação | Outdoor UMi Street Canyon |
| Frequência | 28 GHz |
| Receptores (UEs) | 20, distribuídos a 1,5 m de altura |
| Transmissores (Tx) | 2 — Tx1 em [0, 10, 2] m · Tx2 em [79, 50, 2] m |
| Obstáculos | 16 blocos (atenuação 10–40 dB) — 3 grandes blocos (40 dB), 3 blocos médios (25 dB), 1 bloco intermediário (15 dB) e 9 barreiras baixas (10 dB) |
| Tamanho da RIS | 256 elementos (UPA 16×16) |
| SNR de operação | Tx = 30 dBm · piso de ruído = −80 dBm |

---

## Os Cinco Cenários Comparados

| # | Cenário | Descrição |
|---|---------|-----------|
| 1 | **Sem RIS** | Comunicação direta Tx → Rx, sem superfície refletora |
| 2 | **RIS fixa** | RIS posicionada em [70, 16, 4] m sem otimização |
| 3 | **RIS opt α = 0.1** | AG otimiza priorizando fortemente o pior usuário |
| 4 | **RIS opt α = 0.25** | AG com balanço levemente favorável ao pior usuário |
| 5 | **RIS opt α = 0.5** | AG com peso igual entre SE média e SE mínima |

### Função Fitness do AG

```
fitness = α · mean(SE) + (1 − α) · min(SE)
```

Quanto menor o α, mais o algoritmo penaliza a SE do pior usuário, buscando equidade na rede.

### Parâmetros do AG

| Parâmetro | Valor |
|-----------|-------|
| Tamanho da população | 100 indivíduos |
| Número de gerações | 500 |
| Probabilidade de crossover | 0.8 |
| Probabilidade de mutação | 0.2 |
| Elitismo | 2 indivíduos |

---

## Posições Finais da RIS Otimizada

Após 500 iterações do AG (última linha de cada CSV):

| Cenário | Posição RIS (x, y, z) [m] | Fitness final | SE médio [bps/Hz] |
|---------|--------------------------|---------------|--------------------|
| RIS fixa | [70.0, 16.0, 4.0] | — | 2.3233 |
| RIS opt α = 0.1 | [35.3, 18.9, 4.0] | 0.3826 | 2.5726 |
| RIS opt α = 0.25 | [1.1, 10.5, 4.0] | 0.9331 | 3.7323 |
| RIS opt α = 0.5 | [1.1, 10.5, 4.0] | 1.8661 | 3.7323 |

> Os cenários com α ≥ 0.25 convergiram para uma posição a ~1 m do Tx1 ([0, 10, 2] m). O AG identificou que posicionar a RIS adjacente ao transmissor maximiza o elo Tx → RIS, distribuindo eficientemente o sinal para todos os 20 receptores. O cenário α = 0.1 encontrou uma posição central (~35 m), priorizando cobrir os usuários mais penalizados pelos obstáculos.

---

## Resultados Estatísticos

Saída de `out.txt` (executada em 03/06/2026):

| Cenário | SE Médio (bps/Hz) | SE Percentil 5% (bps/Hz) | SE Mediana (bps/Hz) |
|---------|-------------------|--------------------------|----------------------|
| Sem RIS | 2.2395 | 0.0194 | 0.3143 |
| RIS fixa | 2.3233 | 0.0535 | 0.4301 |
| RIS opt α = 0.1 | 2.5726 | 0.1412 | 0.9817 |
| RIS opt α = 0.25 | **3.7323** | **0.4305** | **3.0890** |
| RIS opt α = 0.5 | **3.7323** | **0.4306** | **3.0889** |

### Ganhos em relação ao cenário sem RIS

| Métrica | RIS fixa | α = 0.1 | α = 0.25 | α = 0.5 |
|---------|----------|---------|----------|---------|
| SE médio | +3.7% | +14.9% | **+66.7%** | **+66.7%** |
| SE percentil 5% | +176% | +628% | **+2118%** | **+2119%** |
| SE mediana | +37% | +212% | **+883%** | **+882%** |

---

## Análise dos Gráficos

### `cdf_comparacao.png` — CDF Empírica da SE

Distribui cumulativa da SE sobre os 20 receptores para cada cenário.

- **Sem RIS e RIS fixa** ficam muito próximas, comprimidas nos valores baixos. Cerca de 50% dos usuários têm SE abaixo de 0.5 bps/Hz — resultado direto dos obstáculos bloqueando a maioria dos enlaces diretos.
- **RIS opt α = 0.1** desloca levemente a cauda inferior: o percentil 5% sai de 0.019 para 0.141 bps/Hz. O corpo da curva (usuários medianos) ainda permanece relativamente baixo.
- **RIS opt α = 0.25 e α = 0.5** produzem uma transformação expressiva: a CDF inteira se desloca para a direita. A mediana passa de 0.31 para ~3.09 bps/Hz. Quase todos os receptores passam a ter SE acima de 0.4 bps/Hz. As duas curvas são praticamente sobrepostas, confirmando que as posições otimizadas convergiram para o mesmo ponto.

### `boxplot_comparacao.png` — Boxplot da SE

Visualização quartil-a-quartil da distribuição de SE por cenário.

- **Sem RIS:** caixa estreitíssima e baixa, com vários outliers superiores. A grande maioria dos usuários tem SE próxima de zero, e apenas alguns poucos (sem obstáculos na linha de visada) atingem valores altos. Reflete alta heterogeneidade.
- **RIS fixa:** praticamente idêntico ao sem RIS. A posição [70, 16, 4] m não beneficia significativamente os usuários com obstrução.
- **RIS opt α = 0.1:** a caixa sobe e alarga, com mediana em ~0.98 bps/Hz (+212%). A variabilidade inter-usuários diminui, mas ainda existe concentração de usuários em valores baixos.
- **RIS opt α = 0.25 e α = 0.5:** caixas deslocadas para a faixa 1–7 bps/Hz, com quartil inferior bem acima de zero. A dispersão entre usuários cai drasticamente: a rede deixa de ter "vencedores e perdedores" e passa a servir todos com qualidade próxima. Os dois cenários são visualmente indistinguíveis.

### `barras_comparacao.png` — SE Individual por UE

Barras agrupadas com a SE de cada um dos 20 receptores para os 5 cenários.

- Sem RIS, há dois grupos distintos: UEs com linha de visada desobstruída (UEs 3–5, 15, 17) atingindo 7–9 bps/Hz, e UEs bloqueados por obstáculos (UEs 1, 8, 12, 14, 16, 18) com SE próxima de zero.
- Com RIS fixa, a distribuição praticamente não muda — confirma que a posição fixa não alcança os usuários mais prejudicados.
- Com α = 0.1, os UEs antes zerados ganham valores modestos (0.13–0.57 bps/Hz). O UE 16, em posição de oclusão total, passa de ~0.000130 para ~0.139 bps/Hz.
- Com α = 0.25 e α = 0.5, quase todos os UEs recebem ganho expressivo: os anteriormente penalizados sobem para 0.9–5 bps/Hz, enquanto os favorecidos mantêm seus valores altos. A única exceção é o **UE 16** (se_16), que permanece com SE ~0.000027 bps/Hz em todos os cenários otimizados — evidência de um receptor em oclusão geométrica irrecuperável pela RIS dentro dos limites de busca definidos.

### `convergencia_AG_comp.png` — Convergência do AG

Curvas de fitness ao longo das iterações (eixo esquerdo para α = 0.1 e α = 0.25; eixo direito para α = 0.5).

- **α = 0.1:** converge rapidamente nas primeiras ~14 iterações (0.296 → 0.383) e estagna. O landscape do fitness é dominado pela função min(SE), que é descontínua e difícil de otimizar — a melhora marginal estagnou cedo.
- **α = 0.25:** convergência mais lenta e gradual até ~iter 30 (0.804 → 0.933). A função mais suave permite ao AG explorar melhor o espaço de busca antes de estabilizar.
- **α = 0.5:** convergência muito rápida nas primeiras ~10 iterações (1.452 → 1.866) com pequenos incrementos posteriores. A SE média é uma função contínua e suave — o AG encontra o ótimo com facilidade.

---

## Conclusões

1. **RIS sem otimização de posição é ineficaz:** o ganho de 3.7% na SE média com RIS fixa é desprezível. A escolha do ponto de instalação é determinante para o benefício da tecnologia.

2. **Otimização com α ≥ 0.25 transforma a rede:** a SE média quase dobra (+67%) e o piso de qualidade (percentil 5%) aumenta mais de 20×, tornando a experiência dos usuários muito mais uniforme.

3. **O AG encontrou uma solução contra-intuitiva:** ao invés de posicionar a RIS no centro do ambiente (posição intuitiva), os cenários α = 0.25 e α = 0.5 convergiram para uma posição quase sobre o Tx1. Isso demonstra que a proximidade ao transmissor maximiza o ganho de array no elo Tx → RIS, compensando a menor flexibilidade angular.

4. **α = 0.1 prioriza equidade mas é limitado pela geometria:** a posição central encontrada (~[35, 19, 4] m) melhora os usuários penalizados, porém não consegue eliminar a oclusão total do UE 16 — um ponto cego estrutural do ambiente.

5. **α = 0.25 e α = 0.5 convergem para o mesmo resultado:** as funções fitness distintas levaram à mesma posição ótima, indicando que nesta região o benefício é robusto independentemente do peso relativo entre média e mínimo.

---

## Como Executar

```matlab
% No MATLAB, com a pasta ris/ no path:
run('inteiro/plot_comparacao.m')
```

O script carrega os `.mat` e os CSVs, imprime a tabela de estatísticas no terminal e salva os três gráficos (CDF, boxplot e barras) como `.png` na própria pasta.
