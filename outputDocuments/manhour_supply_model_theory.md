# マンアワー労働供給モデルの理論的背景と計算過程

## 1. このメモの目的

このメモは、`LabourForce_V1.1.r`で導入したマンアワー型の労働市場モデルについて、理論的背景と計算過程を整理するためのものです。

今回の改修では、労働供給を単なる「労働力人口」ではなく、

- 労働市場に参加する人数の外延: 労働力率 `PartRate`
- 参加者がどれだけ働くかという内延: 労働時間 `H`

に分けて扱い、総労働供給をマンアワーとして

$$
MHS = LS \times H
$$

で定義しています。

また、労働需要も人数ではなくマンアワーとして

$$
MHD = E \times H
$$

を被説明変数にし、供給側・需要側を同じ「時間」単位で比較できるようにしています。

## 2. 事実関係: 現行コードでのモデル構造

### 2.1 入力データと実質化

現行コードでは、消費 `C`を消費デフレータ`D_C`で実質化しています。

```r
D_C       = D_C / 100
C_REAL    = C / D_C
C_REAL_PC = C_REAL / POP
```

ここで、

- `C`: 名目消費
- `D_C`: 消費デフレータ
- `C_REAL`: 実質消費
- `C_REAL_PC`: 1人当たり実質消費

です。

`C_REAL_PC`は、家計の消費・余暇選択を表す労働時間供給式に入ります。

### 2.2 労働供給の外延: 労働力率

労働力率は、0から1の範囲に収まる変数なので、ロジット変換して推計します。

$$
\operatorname{lgtPartRate}
= \log\left(\frac{\operatorname{PartRate}}{1-\operatorname{PartRate}}\right)
$$

BIMETS内の方程式は次の形です。

$$
\begin{aligned}
\operatorname{lgtPartRate}_t
&= b_1
 + b_2 \left(\frac{W_t}{P_t}\right)
 + b_3 U_{rate,t-1}
\end{aligned}
$$

推計後、労働力率は逆ロジットで戻します。

$$
\operatorname{PartRate}_t
= \frac{\exp(\operatorname{lgtPartRate}_t)}
{1+\exp(\operatorname{lgtPartRate}_t)}
$$

労働力人口は、人口と労働力率から定義します。

$$
LS_t = POP_t \times \operatorname{PartRate}_t
$$

### 2.3 労働供給の内延: 労働時間

労働時間`H`は、現実的な範囲を超えて変動しないよう、下限85、上限120の有界ロジット変換を使っています。

実績データから推計用変数を作るときは、

$$
\operatorname{lgtH}_t
= \log\left(\frac{H_t-85}{120-H_t}\right)
$$

と変換します。

BIMETS内では`lgtH`を推計し、`H`は恒等式で戻します。

$$
\begin{aligned}
\operatorname{lgtH}_t
&= h_1
 + h_2 \log\left(\frac{W_t}{P_t}\right)
 + h_3 \log(C\_REAL\_PC_t)
 + h_4 \operatorname{lgtH}_{t-1}
\end{aligned}
$$

$$
H_t
= 85
 + (120-85)
 \frac{\exp(\operatorname{lgtH}_t)}
 {1+\exp(\operatorname{lgtH}_t)}
$$

この式により、どのような`lgtH`が推計されても、`H_t`は必ず85から120の範囲に収まります。

### 2.4 マンアワー労働供給

労働力人口と労働時間を掛け合わせて、供給側のマンアワーを定義します。

$$
MHS_t = LS_t \times H_t
$$

これは、労働供給を「人数」ではなく「人数 × 時間」で測るための中心変数です。

### 2.5 マンアワー労働需要

労働需要側は、就業者数`E`ではなく、マンアワー需要`MHD`を推計対象にしています。

$$
MHD_t = E_t \times H_t
$$

需要方程式は次の形です。

$$
\begin{aligned}
\log(MHD_t)
&= c_1
 + c_2 \log(RY_t)
 + c_3 \log\left(\frac{W_{t-1}}{D\_GDP_{t-1}}\right)
 + c_4 \log(MHD_{t-1})
\end{aligned}
$$

ここで、`W / D_GDP`はGDPデフレータで実質化した時間当たり労働費用に対応します。

## 3. 理論的背景

### 3.1 なぜ人数ではなくマンアワーで見るのか

労働投入は、単なる就業者数だけではなく、何時間働いたかにも依存します。

OECDの生産性統計では、労働投入の望ましい概念として「生産に従事する者の総実労働時間」が用いられています。これは、同じ就業者数でも、短時間労働・長時間労働・休暇・パートタイム比率の変化によって、実際の労働投入が変わるためです。

したがって、人口減少や労働力率だけを見るモデルでは、

- 労働参加者が増えるが、平均労働時間が減る
- 就業者数は横ばいだが、総労働投入は減る
- 短時間就業の増加で人数とマンアワーが乖離する

といった現象を十分に扱えません。

今回のモデルでは、労働投入を

$$
\text{総労働投入}
= \text{労働力人口} \times \text{平均労働時間}
$$

として扱うことで、労働供給の外延と内延を分解しています。

### 3.2 家計の動学的最適化問題

理論的には、家計は各期に消費`C_t`と余暇`L_t`を選び、将来までの効用の割引現在価値を最大化すると考えられます。

代表的には、次のような問題です。

$$
\max_{\{C_t,L_t,H_t,A_{t+1}\}_{t=0}^{\infty}}
E_0 \sum_{t=0}^{\infty} \beta^t u(C_t,L_t)
$$

制約は、時間制約と予算制約です。

$$
T = H_t + L_t
$$

$$
\begin{aligned}
A_{t+1}
&= (1+r_t)A_t
 + W_t H_t
 + \Pi_t
 + TR_t
 - P_t C_t
\end{aligned}
$$

ここで、

- `T`: 利用可能時間
- `H_t`: 労働時間
- `L_t`: 余暇
- `A_t`: 資産
- `r_t`: 利子率
- `W_t`: 名目時間当たり賃金
- `P_t`: 消費者物価または家計消費の価格
- `Π_t`: 利潤・財産所得など
- `TR_t`: 移転所得

です。

この問題の一階条件は、直感的には次の関係を意味します。

$$
\frac{\text{余暇の限界効用}}{\text{消費の限界効用}}
= \text{実質賃金}
$$

数式では、

$$
\frac{u_L(C_t,L_t)}{u_C(C_t,L_t)}
= \frac{W_t}{P_t}
$$

です。

この式は、1時間余暇を減らして働いたときに得られる実質賃金と、失われる余暇の効用価値が均衡する、という条件です。

### 3.3 消費と労働時間の関係

たとえば、効用関数を簡単に

$$
u(C_t,L_t)
= \log(C_t) + \phi \log(L_t)
$$

とします。

このとき、

$$
u_C = \frac{1}{C_t}
$$

$$
u_L = \frac{\phi}{L_t}
$$

なので、一階条件は

$$
\frac{\phi/L_t}{1/C_t}
= \frac{W_t}{P_t}
$$

すなわち、

$$
\frac{\phi C_t}{L_t}
= \frac{W_t}{P_t}
$$

となります。

時間制約`L_t = T - H_t`を代入すると、

$$
\frac{\phi C_t}{T-H_t}
= \frac{W_t}{P_t}
$$

です。

この式から、労働時間は実質賃金、消費水準、余暇の価値に依存することが分かります。

ただし、実質賃金の上昇が労働時間を必ず増やすとは限りません。実質賃金が高くなると、働く誘因が強まる代替効果がある一方で、同じ所得をより少ない労働時間で得られるため余暇を増やす所得効果も生じます。実証式の係数は、この両者の合成効果として解釈されます。

### 3.4 動学性の導入

現実の労働時間は、毎年大きく自由に調整されるわけではありません。

制度、雇用慣行、所定労働時間、パートタイム比率、労働契約、企業側の人員配置などにより、労働時間には慣性があります。

そのため、現行モデルでは、家計の静学的な一階条件をそのまま使うのではなく、前期の労働時間を含む半構造式として実装しています。

$$
\begin{aligned}
\operatorname{lgtH}_t
&= h_1
 + h_2 \log\left(\frac{W_t}{P_t}\right)
 + h_3 \log(C\_REAL\_PC_t)
 + h_4 \operatorname{lgtH}_{t-1}
\end{aligned}
$$

ここで`h4`は、労働時間調整の粘着性を表します。

### 3.5 完全なDSGEではなく、BIMETS上の半構造モデルであること

今回の実装は、完全なDSGEモデルではありません。

完全な動学的一般均衡モデルでは、家計、企業、政府、資産市場、期待形成を同時に解きます。たとえば、消費のEuler方程式は、

$$
u_C(C_t,L_t)
= \beta(1+r_{t+1})E_t\left[u_C(C_{t+1},L_{t+1})\right]
$$

のように書かれます。

一方、今回のBIMETS実装では、

- 動学的最適化問題から得られる「消費、余暇、実質賃金が労働時間を決める」という構造
- 労働時間調整の慣性
- マクロ計量モデルとして推計可能な年次方程式

を組み合わせています。

したがって、理論的には家計最適化問題に基づく半構造モデル、実装上はBIMETSで推計・シミュレーション可能なマクロ計量モデルです。

## 4. 計算過程

### 4.1 データから作成する変数

まず、実績期間のデータから以下を作成します。

$$
RY_t = \frac{Y_t}{D\_GDP_t} \times 100
$$

$$
C\_REAL_t = \frac{C_t}{D\_C_t}
$$

$$
C\_REAL\_PC_t = \frac{C\_REAL_t}{POP_t}
$$

$$
\operatorname{PartRate}_t = \frac{LS_t}{POP_t}
$$

$$
\operatorname{lgtPartRate}_t
= \log\left(\frac{\operatorname{PartRate}_t}{1-\operatorname{PartRate}_t}\right)
$$

$$
\operatorname{lgtH}_t
= \log\left(\frac{H_t-85}{120-H_t}\right)
$$

$$
MHS_t = LS_t \times H_t
$$

$$
MHD_t = E_t \times H_t
$$

### 4.2 外延: 労働力率方程式の推計

労働力率はロジット変換後に推計します。

$$
\begin{aligned}
\operatorname{lgtPartRate}_t
&= b_1
 + b_2 \left(\frac{W_t}{P_t}\right)
 + b_3 U_{rate,t-1}
\end{aligned}
$$

推計後、シミュレーションでは次の順に戻します。

$$
\operatorname{PartRate}_t
= \frac{\exp(\operatorname{lgtPartRate}_t)}
{1+\exp(\operatorname{lgtPartRate}_t)}
$$

$$
LS_t = POP_t \times \operatorname{PartRate}_t
$$

### 4.3 内延: 労働時間方程式の推計

労働時間は有界ロジット変換後に推計します。

$$
\begin{aligned}
\operatorname{lgtH}_t
&= h_1
 + h_2 \log\left(\frac{W_t}{P_t}\right)
 + h_3 \log(C\_REAL\_PC_t)
 + h_4 \operatorname{lgtH}_{t-1}
\end{aligned}
$$

推計後、シミュレーションでは次の式で労働時間に戻します。

$$
H_t
= 85
 + 35\frac{\exp(\operatorname{lgtH}_t)}
 {1+\exp(\operatorname{lgtH}_t)}
$$

このため、

$$
85 < H_t < 120
$$

が常に成立します。

### 4.4 マンアワー労働供給

労働力人口と労働時間を掛けて、供給マンアワーを計算します。

$$
MHS_t = LS_t \times H_t
$$

ここで、`LS_t`は労働参加の外延、`H_t`は労働時間の内延です。

したがって、`MHS_t`の変化は、

- 人口・労働力率の変化
- 平均労働時間の変化

に分解できます。

### 4.5 マンアワー労働需要

需要側は、

$$
\begin{aligned}
\log(MHD_t)
&= c_1
 + c_2 \log(RY_t)
 + c_3 \log\left(\frac{W_{t-1}}{D\_GDP_{t-1}}\right)
 + c_4 \log(MHD_{t-1})
\end{aligned}
$$

で推計します。

実質GDP`RY`が増えると労働需要が増え、実質時間賃金`W / D_GDP`が上がると労働需要が抑制される、という生産側の労働需要関数に対応しています。

### 4.6 需給ギャップと失業率

時間ベースの労働需給バランスは、

$$
\frac{MHD_t}{MHS_t}
$$

で表します。

失業率のロジット変換は、このマンアワー需給比率に反応します。

$$
\begin{aligned}
\operatorname{lgtU\_rate}_t
&= a_1
 + a_2 \left(\frac{MHD_t}{MHS_t}\right)
 + a_3 \operatorname{lgtU\_rate}_{t-1}
\end{aligned}
$$

失業率は逆ロジットで戻します。

$$
U\_rate_t
= \frac{\exp(\operatorname{lgtU\_rate}_t)}
{1+\exp(\operatorname{lgtU\_rate}_t)}
$$

### 4.7 潜在需要としてのEと実現就業者数としてのE_est

`E`は、マンアワー需要を労働時間で割り戻した潜在的な必要就業者数です。

$$
E_t = \frac{MHD_t}{H_t}
$$

ただし、定義上、実現就業者数は労働力人口を超えられません。

そのため、モデルでは実現就業者数を

$$
E\_est_t = LS_t \times (1-U\_rate_t)
$$

として定義しています。

このため、

$$
E\_est_t \le LS_t
$$

が成立します。

`E_t > LS_t`となる場合は、実現就業者数が労働力人口を超えたという意味ではなく、労働需要側から見た潜在的な必要人数が労働供給制約を上回っている、すなわち未充足労働需要があると解釈します。

## 5. 有界ロジット変換の意味

### 5.1 通常の水準推計の問題

`log(H)`を直接推計すると、シミュレーション期間で労働時間が極端に低下または上昇する可能性があります。

たとえば、前回の推計では、`H`が長期的に非常に低い値へ向かい、供給マンアワーが過度に縮小する経路が出ました。

### 5.2 有界ロジット変換

そこで、`H`を直接推計せず、`H`を下限85・上限120の範囲に写す潜在変数`lgtH`を推計します。

変換は、

$$
\operatorname{lgtH}
= \log\left(\frac{H-85}{120-H}\right)
$$

です。

逆変換は、

$$
H
= 85
 + 35\frac{\exp(\operatorname{lgtH})}
 {1+\exp(\operatorname{lgtH})}
$$

です。

この変換の利点は、`lgtH`自体は理論上どのような実数値を取っても、逆変換後の`H`は必ず85から120の間に収まることです。

### 5.3 境界付近での変化

`p_t = exp(lgtH_t) / (1 + exp(lgtH_t))`とおくと、

$$
H_t = 85 + 35p_t
$$

です。

`lgtH`に対する`H`の変化は、

$$
\frac{\partial H_t}{\partial \operatorname{lgtH}_t}
= 35p_t(1-p_t)
$$

です。

`H`が下限85または上限120に近づくと、`p_t`は0または1に近づき、`p_t(1-p_t)`は小さくなります。

つまり、境界に近づくほど、同じ`lgtH`の変化でも`H`の変化幅は小さくなります。これにより、労働時間が非現実的に範囲外へ飛び出すことを防げます。

## 6. モデルの読み方

### 6.1 労働供給は2段階で読む

労働供給は次の2段階で解釈します。

$$
POP
\rightarrow \operatorname{PartRate}
\rightarrow LS
$$

$$
\left(\frac{W}{P},\ C\_REAL\_PC,\ H_{t-1}\right)
\rightarrow H
$$

これらを合わせて、

$$
MHS = LS \times H
$$

が決まります。

### 6.2 人数不足と時間不足を分けて読む

`LS`が低下している場合は、人数面での供給制約です。

`H`が低下している場合は、1人当たり労働時間の低下による供給制約です。

`MHS`が低下している場合は、人数と時間の合成効果として、総労働投入が低下していることを意味します。

### 6.3 需要側のEは潜在必要人数

`E = MHD / H`は、需要マンアワーを労働時間で割った潜在的な必要人数です。

したがって、`E`が`LS`を超える場合でも、それは定義違反ではありません。

実現就業者数としては、

$$
E\_est = LS \times (1-U\_rate)
$$

を見ます。

政策分析では、

$$
E - E\_est
$$

または

$$
MHD - MHS
$$

を未充足労働需要・労働投入不足の指標として解釈できます。

## 7. 理論上の位置づけ

### 7.1 RBC/DSGE型モデルとの関係

King, Plosser and Rebelo (1988)の基本的な実物的景気循環モデルでは、資本蓄積に加え、労働供給の選択を含む新古典派モデルが景気変動分析の基礎として位置づけられています。

今回のモデルも、完全なDSGE解法ではありませんが、

- 消費と余暇の選択
- 実質賃金に対する労働時間反応
- 動学的な調整

を供給側に取り込んでいる点で、同じ理論的発想に基づく半構造モデルです。

### 7.2 外延と内延の分離

Hansen (1985)やRogerson (1988)の不可分労働の議論では、個人レベルでは働く・働かないの選択が不連続でも、集計レベルでは労働供給が変動し得ることが示されています。

今回のモデルでは、そこまで厳密な不可分労働モデルは置いていませんが、

- 労働力率: 働く側に入るかどうか
- 労働時間: 働く人がどれだけ働くか

を分けることで、外延と内延を区別しています。

### 7.3 税・制度・選好の扱い

Prescott (2004)などの研究では、労働所得課税や制度が国・時点間の労働時間差を説明し得ることが議論されています。

現行モデルでは、税率や社会保険料率を明示的には入れていません。

そのため、`lgtH`方程式の定数項、実質賃金係数、実質消費係数、ラグ項は、制度・慣行・選好・税制の複合効果を含む縮約形として解釈する必要があります。

## 8. 限界と今後の改善余地

### 8.1 完全な最適化モデルではない

現行モデルは、家計の動学的最適化問題そのものを数値的に解くモデルではありません。

あくまで、最適化問題から導かれる関係をBIMETSで推計可能な形に落とした半構造モデルです。

### 8.2 労働時間の下限・上限は外生的な較正値

`H`の下限85、上限120は、理論から一意に決まる値ではありません。

これは、実績値の範囲、制度的に考えられる労働時間、シミュレーションの安定性を踏まえて置いた較正値です。

感度分析としては、たとえば次のケースを比較できます。

- 下限80・上限120
- 下限85・上限120
- 下限90・上限120
- 下限85・上限115

### 8.3 労働力率にも上限を入れる余地

`PartRate`はロジット変換により0から1の範囲には収まりますが、政策的・制度的に見て高すぎる値になる可能性があります。

必要であれば、労働力率にも有界ロジットを使い、

$$
\operatorname{PartRate}_{min}
< \operatorname{PartRate}
< \operatorname{PartRate}_{max}
$$

を明示的に課すことができます。

### 8.4 MHDとMHSのギャップを賃金・時間に戻す余地

現行モデルでは、`MHD/MHS`は失業率に反応しますが、労働時間`H`や賃金`W`へのフィードバックは限定的です。

より均衡調整を強めるには、

$$
\Delta \log(W_t)
= \cdots
 + \gamma \log\left(\frac{MHD_t}{MHS_t}\right)
$$

または

$$
\operatorname{lgtH}_t
= \cdots
 + \eta \log\left(\frac{MHD_t}{MHS_t}\right)
$$

のように、マンアワー需給ギャップを賃金・労働時間へ戻す式を追加することが考えられます。

## 9. 参考文献・資料

- OECD (2018), *OECD Compendium of Productivity Indicators 2018*, "Measuring hours worked".  
  https://www.oecd.org/en/publications/oecd-compendium-of-productivity-indicators-2018_pdtvy-2018-en/full-report/component-37.html

- OECD (2001), *Measuring Productivity: OECD Manual*.  
  https://www.oecd.org/content/dam/oecd/en/publications/reports/2001/07/measuring-productivity-oecd-manual_g1gh2484/9789264194519-en.pdf

- King, R. G., Plosser, C. I., and Rebelo, S. T. (1988), "Production, Growth and Business Cycles: I. The Basic Neoclassical Model", *Journal of Monetary Economics*, 21(2-3), 195-232.  
  https://www.sciencedirect.com/science/article/pii/030439328890030X

- Hansen, G. D. (1985), "Indivisible Labor and the Business Cycle", *Journal of Monetary Economics*, 16(3), 309-327.  
  https://cir.nii.ac.jp/crid/1361418520167962880

- Rogerson, R. (1988), "Indivisible Labor, Lotteries and Equilibrium", *Journal of Monetary Economics*, 21(1), 3-16.  
  https://collaborate.princeton.edu/en/publications/indivisible-labor-lotteries-and-equilibrium/

- Prescott, E. C. (2004), "Why Do Americans Work So Much More than Europeans?", NBER Working Paper No. 10316.  
  https://www.nber.org/papers/w10316
