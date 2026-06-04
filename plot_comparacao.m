% Comparacao: RIS otimizada (AG) vs RIS fixa vs Sem RIS
% Carrega resultados .mat e CSVs do AG
base = 'C:\Users\Multivac\Desktop\IgorAntunesCellFree\ris\inteiro\';

%% ===== Carregar .mat =====
m_fix = load([base 'ris_fixa.mat']);
m_sem = load([base 'sem_ris.mat']);

% Campos esperados: SE (K x 1) e SINRdB (K x 1)
se_fix = m_fix.SE(:);
se_sem = m_sem.SE(:);

%% ===== Carregar CSVs AG (melhor candidato = ultima linha) =====
function se = last_se(csvfile)
    T = readtable(csvfile);
    se_cols = T.Properties.VariableNames;
    se_cols = se_cols(startsWith(se_cols,'se_'));
    se = table2array(T(end, se_cols))';
end

se_a01  = last_se([base 'otim_AG_20260603_163524.csv']);  % alpha=0.1
se_a025 = last_se([base 'otim_AG_20260603_165941.csv']);  % alpha=0.25
se_a05  = last_se([base 'otim_AG_20260603_165237.csv']);  % alpha=0.5

%% ===== Estatisticas =====
datasets = {se_sem, se_fix, se_a01, se_a025, se_a05};
labels   = {'No RIS','RIS fixed','RIS opt \alpha=0.1','RIS opt \alpha=0.25','RIS opt \alpha=0.5'};
cores    = {[0.5 0.5 0.5],[0.2 0.2 0.8],[0.85 0.25 0.10],[0.18 0.65 0.30],[0.80 0.40 0.00]};
estilos  = {'--','-.','-','-','-'};

fprintf('\n%-25s  %8s  %8s  %8s\n','Cenario','Medio','5 pct','Mediana');
fprintf('%s\n',repmat('-',55,1));
for i=1:numel(datasets)
    se=datasets{i}; se=se(~isnan(se));
    med=mean(se); p5=prctile(se,5); md=median(se);
    fprintf('%-25s  %8.4f  %8.4f  %8.4f\n',labels{i},med,p5,md);
end

%% ===== Figura 1: CDF empirica =====
fig1=figure('Color','w','Position',[60 60 800 480],'Name','CDF SE');
hold on;
for i=1:numel(datasets)
    se=sort(datasets{i}(:)); n=numel(se);
    cdf=(1:n)/n;
    plot(se,cdf,'LineStyle',estilos{i},'Color',cores{i},'LineWidth',2.0,...
        'DisplayName',labels{i});
end
xline(0,'k:','HandleVisibility','off');
xlabel('SE (bps/Hz)'); ylabel('CDF');
legend('Location','southeast','FontSize',10);
grid on; box on;
saveas(fig1,[base 'cdf_comparacao.png']);

%% ===== Figura 2: Boxplot =====
fig2=figure('Color','w','Position',[60 60 860 480],'Name','Boxplot SE');
Kmin=min(cellfun(@numel,datasets));
mat=zeros(Kmin,numel(datasets));
for i=1:numel(datasets), mat(:,i)=datasets{i}(1:Kmin); end
bp=boxplot(mat,'Labels',labels);
set(bp,'LineWidth',1.6);
% Colore cada caixa
h_box=findobj(gca,'Tag','Box');
for i=1:numel(h_box)
    idx=numel(h_box)-i+1;  % boxplot inverte a ordem
    patch(get(h_box(i),'XData'),get(h_box(i),'YData'),cores{idx},'FaceAlpha',0.4);
end
ylabel('SE (bps/Hz)'); grid on; box on;
set(gca,'XTickLabelRotation',15);
saveas(fig2,[base 'boxplot_comparacao.png']);

%% ===== Figura 3: SE por UE (barras) =====
fig3=figure('Color','w','Position',[60 60 950 440],'Name','SE por UE');
Kue=min(cellfun(@numel,datasets));
x_ue=1:Kue;
width=0.15; offsets=linspace(-0.30,0.30,numel(datasets));
hold on;
for i=1:numel(datasets)
    se=datasets{i}(1:Kue);
    bar(x_ue+offsets(i), se, width,'FaceColor',cores{i},'EdgeColor','none','DisplayName',labels{i});
end
xlabel('UE index'); ylabel('SE (bps/Hz)');
legend('Location','northeast','FontSize',9);
xticks(x_ue); grid on; box on;
saveas(fig3,[base 'barras_comparacao.png']);

fprintf('\nGraficos salvos em:\n  cdf_comparacao.png\n  boxplot_comparacao.png\n  barras_comparacao.png\n');
