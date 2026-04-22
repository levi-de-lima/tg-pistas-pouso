
export default function Windrose() {
  const cx = 240, cy = 240, maxR = 170;

  // Dados simulados: área total (ha) por setor × semestre
  const data = {
    0:   { "2020.0": 8,  "2021.0": 5                          },
    45:  { "2021.0": 12, "2021.5": 18, "2022.0": 6            },
    90:  { "2021.5": 28, "2022.0": 42, "2022.5": 30, "2023.0": 14 },
    135: { "2022.0": 22, "2022.5": 35, "2023.0": 18           },
    180: { "2020.0": 4,  "2021.0": 3                          },
    225: { "2021.5": 5,  "2022.0": 4                          },
    270: { "2022.5": 10, "2023.0": 16, "2023.5": 8            },
    315: { "2020.5": 6,  "2021.0": 5                          },
  };

  const semestres = ["2020.0","2020.5","2021.0","2021.5","2022.0","2022.5","2023.0","2023.5"];
  const cores = {
    "2020.0": "#4e79a7",
    "2020.5": "#6baed6",
    "2021.0": "#74c476",
    "2021.5": "#41ab5d",
    "2022.0": "#fdae6b",
    "2022.5": "#f46d43",
    "2023.0": "#d62728",
    "2023.5": "#8c1b1b",
  };

  const maxTotal = Math.max(
    ...Object.values(data).map(d => Object.values(d).reduce((a, b) => a + b, 0))
  );

  const toRad = (deg) => ((deg - 90) * Math.PI) / 180;

  const renderSetor = (anguloCentral, dadosSetor) => {
    const sa = toRad(anguloCentral - 22.5);
    const ea = toRad(anguloCentral + 22.5);
    let rAtual = 0;
    const paths = [];

    for (const sem of semestres) {
      if (!dadosSetor[sem]) continue;
      const rInterno = (rAtual / maxTotal) * maxR;
      rAtual += dadosSetor[sem];
      const rExterno = (rAtual / maxTotal) * maxR;

      const x1 = cx + rInterno * Math.cos(sa);
      const y1 = cy + rInterno * Math.sin(sa);
      const x2 = cx + rExterno * Math.cos(sa);
      const y2 = cy + rExterno * Math.sin(sa);
      const x3 = cx + rExterno * Math.cos(ea);
      const y3 = cy + rExterno * Math.sin(ea);
      const x4 = cx + rInterno * Math.cos(ea);
      const y4 = cy + rInterno * Math.sin(ea);

      const d =
        rInterno < 0.5
          ? `M ${cx} ${cy} L ${x2} ${y2} A ${rExterno} ${rExterno} 0 0 1 ${x3} ${y3} Z`
          : `M ${x1} ${y1} L ${x2} ${y2} A ${rExterno} ${rExterno} 0 0 1 ${x3} ${y3} L ${x4} ${y4} A ${rInterno} ${rInterno} 0 0 0 ${x1} ${y1} Z`;

      paths.push(
        <path key={sem} d={d} fill={cores[sem]} stroke="white" strokeWidth="0.8" opacity={0.9} />
      );
    }
    return paths;
  };

  const setores = [0, 45, 90, 135, 180, 225, 270, 315];
  const rotulosSetor = ["0°","45°","90°","135°","180°","225°","270°","315°"];
  const gridRatios = [0.25, 0.5, 0.75, 1.0];
  const pistaDir = 30; // direção simulada da pista (PCA), em graus relativos

  return (
    <div style={{ fontFamily: "sans-serif", padding: 24, background: "#fafafa", minHeight: "100vh" }}>
      <h2 style={{ marginBottom: 4, color: "#333" }}>Windrose — Pista 11 (simulado)</h2>
      <p style={{ color: "#666", fontSize: 13, marginTop: 0, marginBottom: 20 }}>
        Cada setor = 45°. Altura da barra = área total de mineração (ha). Cor = semestre.
      </p>

      <div style={{ display: "flex", gap: 40, alignItems: "flex-start", flexWrap: "wrap" }}>
        <svg width={480} height={480}>
          {/* Círculos de referência */}
          {gridRatios.map((r, i) => (
            <g key={i}>
              <circle cx={cx} cy={cy} r={r * maxR} fill="none" stroke="#ccc" strokeWidth={0.8} strokeDasharray="4 3" />
              <text x={cx + 3} y={cy - r * maxR + 11} fontSize={9} fill="#aaa">
                {Math.round(r * maxTotal)} ha
              </text>
            </g>
          ))}

          {/* Linhas divisórias dos setores */}
          {setores.map((ang) => {
            const rad = toRad(ang - 22.5);
            return (
              <line
                key={ang}
                x1={cx} y1={cy}
                x2={cx + (maxR + 8) * Math.cos(rad)}
                y2={cy + (maxR + 8) * Math.sin(rad)}
                stroke="#bbb" strokeWidth={0.7}
              />
            );
          })}

          {/* Barras empilhadas */}
          {setores.map((ang) => renderSetor(ang, data[ang] || {}))}

          {/* Indicador da orientação da pista (PCA) */}
          {[pistaDir, pistaDir + 180].map((ang, i) => {
            const rad = toRad(ang);
            const r = 22;
            return (
              <line
                key={i}
                x1={cx} y1={cy}
                x2={cx + r * Math.cos(rad)}
                y2={cy + r * Math.sin(rad)}
                stroke="#222" strokeWidth={3} strokeLinecap="round"
              />
            );
          })}
          <circle cx={cx} cy={cy} r={4} fill="#222" />
          <text x={cx + 6} y={cy - 26} fontSize={9} fill="#333" fontWeight="bold">pista</text>

          {/* Rótulos dos setores */}
          {setores.map((ang, i) => {
            const rad = toRad(ang);
            const r = maxR + 22;
            return (
              <text
                key={ang}
                x={cx + r * Math.cos(rad)}
                y={cy + r * Math.sin(rad)}
                textAnchor="middle"
                dominantBaseline="middle"
                fontSize={11}
                fill="#555"
              >
                {rotulosSetor[i]}
              </text>
            );
          })}
        </svg>

        {/* Legenda */}
        <div>
          <p style={{ fontSize: 13, fontWeight: "bold", color: "#444", marginBottom: 10 }}>
            Semestre (fill)
          </p>
          {semestres.map((sem) => (
            <div key={sem} style={{ display: "flex", alignItems: "center", marginBottom: 6 }}>
              <div
                style={{
                  width: 16, height: 16, background: cores[sem],
                  marginRight: 8, borderRadius: 3, border: "1px solid #ccc"
                }}
              />
              <span style={{ fontSize: 13, color: "#444" }}>{sem}</span>
            </div>
          ))}

          <div style={{ marginTop: 24, padding: 12, background: "#f0f0f0", borderRadius: 6, maxWidth: 220, fontSize: 12, color: "#555" }}>
            <strong>Como ler:</strong><br /><br />
            → <b>Direção</b>: onde está a mineração em relação à pista<br /><br />
            → <b>Comprimento</b>: área total naquele setor<br /><br />
            → <b>Cor empilhada</b>: quando (semestre) essa área foi detectada<br /><br />
            → <b>Traço central</b>: orientação da pista (calculada por PCA)
          </div>
        </div>
      </div>

      <p style={{ fontSize: 11, color: "#999", marginTop: 16 }}>
        * Dados simulados para visualização. Neste exemplo, a maior concentração de mineração está nos setores E–SE (~90°–135°), com expansão acelerada em 2022.
      </p>
    </div>
  );
}
