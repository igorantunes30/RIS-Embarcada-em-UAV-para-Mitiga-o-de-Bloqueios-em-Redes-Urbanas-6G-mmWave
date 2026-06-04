function SimRIS_GUI()
% SimRIS_GUI - APLICACAO UNICA (auto-contida) SimRIS:
%   * parametros SimRIS (Environment, Scenario, Frequency, ArrayType, N, Nsym)
%   * Tx/Rx/RIS via CSV (coluna 'type') ou gerador aleatorio (posicoes inteiras)
%   * editor de obstaculos (predios AABB + atenuacao dB) com add/del
%   * topologia 3D movel; arestas RIS->Rx coloridas por SE
%   * RUN SimRIS: SINR multi-Tx por UE (servidor = Tx mais forte; demais Tx
%     interferem sob a MESMA fase da RIS) -> SE medio, SE 5%
%   * Otimizacao da posicao da RIS: FPA ou AG (params editaveis), rastro em
%     tempo real, botao PARAR, multi-processo (parfor), CSV em tempo real
%   * area automatica por ambiente (Indoor 80x50 / Outdoor 300x200)
% TUDO neste arquivo: app + outdoor_config + occlusao_att_dB + SimRIS_v18.
%
% CSV esperado (cabecalho): type,x,y,z  (type = RIS, Tx ou Rx).

    here = fileparts(mfilename('fullpath'));

    cfg = outdoor_config();
    B0 = cfg.blockers;
    SNR_lin = cfg.SNR_lin;
    Lb0 = cfg.Lb; Ub0 = cfg.Ub; alpha0 = cfg.alpha;

    % nos (default). CSV / gerador sobrescrevem.
    TxL = [0 100 10];
    RxL = [85 95 1.5];
    RIS = [50 130 30];
    area = [300 200];          % Outdoor=300x200, Indoor=80x50 (auto pelo Environment)
    stopFlag = false;          % pedido de parada da otimizacao

    % ================= layout =================
    f = figure('Name','SimRIS - Multi Tx/Rx + Topologia 3D + Otimizacao','Color','w', ...
        'Position',[30 30 1360 880],'NumberTitle','off');
    pc = uipanel(f,'Units','normalized','Position',[0.004 0.004 0.31 0.992], ...
                 'Title','Controles','FontWeight','bold','BackgroundColor','w');
    pg = uipanel(f,'Units','normalized','Position',[0.318 0.004 0.678 0.992], ...
                 'Title','Topologia 3D (arraste p/ girar)','FontWeight','bold','BackgroundColor','w');
    ax = axes(pg,'Units','normalized','Position',[0.08 0.08 0.86 0.88]);
    logLines={};

    % helpers (parent variavel)
    TL=@(par,p,s) uicontrol(par,'Style','text','Units','normalized','Position',p,'String',s, ...
        'BackgroundColor','w','HorizontalAlignment','left','FontWeight','bold','FontSize',8);
    TC=@(par,p,s) uicontrol(par,'Style','text','Units','normalized','Position',p,'String',s, ...
        'BackgroundColor','w','HorizontalAlignment','center','FontSize',8);
    ED=@(par,p,v) uicontrol(par,'Style','edit','Units','normalized','Position',p,'String',num2str(v),'BackgroundColor','w');
    PP=@(par,p,o,v) uicontrol(par,'Style','popupmenu','Units','normalized','Position',p,'String',o,'Value',v,'BackgroundColor','w');

    % --- botoes de acao + saida (sempre visiveis, fora das abas) ---
    uicontrol(pc,'Style','pushbutton','Units','normalized','Position',[0.03 0.270 0.30 0.034],'String','ATUALIZAR','FontWeight','bold','BackgroundColor',[.85 .92 .8],'Callback',@redraw);
    uicontrol(pc,'Style','pushbutton','Units','normalized','Position',[0.35 0.270 0.33 0.034],'String','RUN SimRIS','FontWeight','bold','BackgroundColor',[.80 .88 .98],'Callback',@runSim);
    uicontrol(pc,'Style','pushbutton','Units','normalized','Position',[0.70 0.270 0.27 0.034],'String','Save .mat','Callback',@saveMat);
    txtOut=uicontrol(pc,'Style','text','Units','normalized','Position',[0.03 0.142 0.94 0.122], ...
        'String','','BackgroundColor',[.96 .96 .9],'HorizontalAlignment','left','FontName','Consolas','FontSize',9);
    TL(pc,[0.03 0.118 0.30 0.02],'LOG (por iteracao):');
    logBox=uicontrol(pc,'Style','text','Units','normalized','Position',[0.03 0.006 0.94 0.112], ...
        'String','','BackgroundColor',[.12 .12 .12],'ForegroundColor',[.6 1 .6], ...
        'HorizontalAlignment','left','FontName','Consolas','FontSize',8);

    % --- abas ---
    tg=uitabgroup(pc,'Units','normalized','Position',[0.005 0.305 0.99 0.69]);
    t1=uitab(tg,'Title','Cenario','BackgroundColor','w');
    t2=uitab(tg,'Title','Otimizacao','BackgroundColor','w');

    % ===== ABA 1: CENARIO =====
    TL(t1,[0.03 0.945 0.30 0.04],'Environment');
    dEnv=PP(t1,[0.34 0.948 0.63 0.045], {'Indoor (InH Office)','Outdoor (UMi Street Canyon)'},2);
    TL(t1,[0.03 0.895 0.30 0.04],'RIS plane');
    dSc =PP(t1,[0.34 0.898 0.63 0.045], {'xz plane (Scenario 1)','yz plane (Scenario 2)'},1);
    TL(t1,[0.03 0.845 0.30 0.04],'Frequency');
    dFr =PP(t1,[0.34 0.848 0.63 0.045], {'28 GHz','73 GHz'},2);
    TL(t1,[0.03 0.795 0.30 0.04],'Array Type');
    dAT =PP(t1,[0.34 0.798 0.63 0.045], {'Uniform Linear Array','Uniform Planar Array'},2);

    TC(t1,[0.03 0.745 0.21 0.035],'N (RIS)'); TC(t1,[0.25 0.745 0.22 0.035],'Nsym (MC)'); TC(t1,[0.48 0.745 0.22 0.035],'Reps (RUN)'); TC(t1,[0.71 0.745 0.27 0.035],'Modo Canal');
    eN=ED(t1,[0.03 0.705 0.21 0.04],256); eNsym=ED(t1,[0.25 0.705 0.22 0.04],10); eReps=ED(t1,[0.48 0.705 0.22 0.04],1);
    dMod=PP(t1,[0.71 0.700 0.27 0.05],{'Estocástico (MC)','Determinístico'},1);

    TL(t1,[0.03 0.655 0.16 0.038],'RIS:');
    lblRIS=uicontrol(t1,'Style','text','Units','normalized','Position',[0.20 0.655 0.40 0.04], ...
        'String',mat2str(RIS),'BackgroundColor',[.94 .96 .94],'HorizontalAlignment','left','FontSize',8);
    cNoRIS=uicontrol(t1,'Style','checkbox','Units','normalized','Position',[0.62 0.655 0.36 0.04], ...
        'String','sem RIS (Tx-Rx direto)','Value',0,'BackgroundColor','w','FontSize',8,'Callback',@redraw);
    TL(t1,[0.03 0.610 0.94 0.035],'RIS/Tx/Rx vem de CSV ou do gerador:');

    uicontrol(t1,'Style','pushbutton','Units','normalized','Position',[0.03 0.555 0.44 0.05], ...
        'String','Carregar CSV (Tx/Rx)','Callback',@loadCSV);
    lblNos=uicontrol(t1,'Style','text','Units','normalized','Position',[0.49 0.560 0.48 0.04], ...
        'String','Tx:1 Rx:1','BackgroundColor','w','FontWeight','bold','FontSize',8);

    TC(t1,[0.03 0.500 0.10 0.035],'nTx'); eGTx=ED(t1,[0.13 0.500 0.13 0.045],2);
    TC(t1,[0.28 0.500 0.10 0.035],'nRx'); eGRx=ED(t1,[0.38 0.500 0.13 0.045],20);
    uicontrol(t1,'Style','pushbutton','Units','normalized','Position',[0.53 0.500 0.44 0.045], ...
        'String','Gerar CSV aleatorio','FontWeight','bold','BackgroundColor',[.98 .92 .80],'Callback',@genRandom);

    TL(t1,[0.03 0.450 0.52 0.035],'Obstaculos (AABB + att dB):');
    cPar2=uicontrol(t1,'Style','checkbox','Units','normalized','Position',[0.56 0.450 0.42 0.035], ...
        'String','multi-processo (parfor)','Value',0,'BackgroundColor','w','FontSize',8,'Callback',@syncPar);
    tbl=uitable(t1,'Units','normalized','Position',[0.03 0.085 0.94 0.36], ...
        'Data',B0,'ColumnName',{'xmin','xmax','ymin','ymax','zmin','zmax','att_dB'}, ...
        'ColumnEditable',true(1,7),'ColumnWidth',repmat({44},1,7),'RowName',[]);
    uicontrol(t1,'Style','pushbutton','Units','normalized','Position',[0.03 0.02 0.46 0.05],'String','+ Obstaculo','Callback',@addRow);
    uicontrol(t1,'Style','pushbutton','Units','normalized','Position',[0.51 0.02 0.46 0.05],'String','- Obstaculo','Callback',@delRow);

    % ===== ABA 2: OTIMIZACAO =====
    TL(t2,[0.03 0.945 0.30 0.04],'Otimizador');
    dOpt=PP(t2,[0.34 0.948 0.63 0.045], {'Nenhum','FPA (Flower Pollination)','AG (Algoritmo Genetico)','Sequencial (Grid)'},2);
    TC(t2,[0.03 0.895 0.45 0.035],'alpha (media vs min)'); eAlpha=ED(t2,[0.52 0.898 0.20 0.04],alpha0);
    cInt=uicontrol(t2,'Style','checkbox','Units','normalized','Position',[0.74 0.895 0.24 0.04], ...
        'String','xyz inteiro','Value',1,'BackgroundColor','w','FontSize',8);
    cPar=uicontrol(t2,'Style','checkbox','Units','normalized','Position',[0.03 0.728 0.50 0.035], ...
        'String','multi-processo (parfor)','Value',0,'BackgroundColor','w','FontSize',8,'Callback',@syncPar);
    cSave=uicontrol(t2,'Style','checkbox','Units','normalized','Position',[0.54 0.728 0.44 0.035], ...
        'String','salvar CSV (tempo real)','Value',1,'BackgroundColor','w','FontSize',8);

    TL(t2,[0.03 0.850 0.50 0.035],'Caixa de busca RIS [x y z] (m):');
    cFixZ=uicontrol(t2,'Style','checkbox','Units','normalized','Position',[0.54 0.850 0.27 0.035], ...
        'String','altura z fixa','Value',0,'BackgroundColor','w','FontSize',8);
    eFixZ=ED(t2,[0.83 0.848 0.14 0.04],30);
    TC(t2,[0.03 0.815 0.10 0.03],'Lb'); eLb=ED(t2,[0.14 0.812 0.83 0.04],Lb0);
    TC(t2,[0.03 0.770 0.10 0.03],'Ub'); eUb=ED(t2,[0.14 0.767 0.83 0.04],Ub0);

    % --- painel FPA (so aparece se Otimizador=FPA) ---
    pFPA=uipanel(t2,'Units','normalized','Position',[0.02 0.40 0.96 0.32], ...
        'Title','Parametros FPA','FontWeight','bold','BackgroundColor','w');
    TC(pFPA,[0.03 0.80 0.30 0.10],'n (pop)');     eFn =ED(pFPA,[0.34 0.80 0.16 0.13],20);
    TC(pFPA,[0.52 0.80 0.30 0.10],'p (switch)');  eFp =ED(pFPA,[0.83 0.80 0.14 0.13],0.8);
    TC(pFPA,[0.03 0.58 0.30 0.10],'iteracoes');   eFit=ED(pFPA,[0.34 0.58 0.16 0.13],40);
    TC(pFPA,[0.52 0.58 0.18 0.10],'gamma');       eFg =ED(pFPA,[0.71 0.58 0.12 0.13],0.1);
    TC(pFPA,[0.03 0.36 0.30 0.10],'beta');        eFb =ED(pFPA,[0.34 0.36 0.16 0.13],1.5);
    TL(pFPA,[0.03 0.06 0.94 0.16],'Levy global + polinizacao local.');

    % --- painel AG (so aparece se Otimizador=AG) ---
    pAG=uipanel(t2,'Units','normalized','Position',[0.02 0.40 0.96 0.32], ...
        'Title','Parametros AG','FontWeight','bold','BackgroundColor','w','Visible','off');
    TC(pAG,[0.03 0.80 0.30 0.10],'pop');         eAp =ED(pAG,[0.34 0.80 0.16 0.13],20);
    TC(pAG,[0.52 0.80 0.30 0.10],'geracoes');    eAg =ED(pAG,[0.83 0.80 0.14 0.13],40);
    TC(pAG,[0.03 0.58 0.30 0.10],'pc (cross)');  eApc=ED(pAG,[0.34 0.58 0.16 0.13],0.8);
    TC(pAG,[0.52 0.58 0.30 0.10],'pm (mut)');    eApm=ED(pAG,[0.83 0.58 0.14 0.13],0.2);
    TC(pAG,[0.03 0.36 0.30 0.10],'elite');       eAe =ED(pAG,[0.34 0.36 0.16 0.13],2);
    TL(pAG,[0.03 0.06 0.94 0.16],'Torneio + crossover blend + mutacao.');

    % --- painel Sequencial (so aparece se Otimizador=Sequencial) ---
    pSeq=uipanel(t2,'Units','normalized','Position',[0.02 0.40 0.96 0.32], ...
        'Title','Parametros Sequencial (Grid)','FontWeight','bold','BackgroundColor','w','Visible','off');
    TC(pSeq,[0.03 0.78 0.35 0.12],'Passo (m)'); eStep=ED(pSeq,[0.40 0.78 0.18 0.14],5);
    lblNpts=uicontrol(pSeq,'Style','text','Units','normalized','Position',[0.03 0.30 0.94 0.38],...
        'String','','BackgroundColor','w','HorizontalAlignment','left','FontSize',8);
    TL(pSeq,[0.03 0.06 0.94 0.16],'Varre todos os pontos do grid. Garante otimo global na grade.');

    dOpt.Callback=@toggleOpt; toggleOpt();   % visibilidade inicial conforme dropdown
    dEnv.Callback=@onEnv;                     % area muda com o ambiente

    uicontrol(t2,'Style','pushbutton','Units','normalized','Position',[0.03 0.30 0.62 0.06], ...
        'String','OTIMIZAR RIS','FontWeight','bold','FontSize',10,'BackgroundColor',[.95 .85 .6],'Callback',@optimizeRIS);
    uicontrol(t2,'Style','pushbutton','Units','normalized','Position',[0.67 0.30 0.30 0.06], ...
        'String','PARAR','FontWeight','bold','FontSize',10,'BackgroundColor',[.95 .6 .6],'Callback',@(~,~) setStop());
    TL(t2,[0.03 0.255 0.94 0.035],'Otimiza posicao da RIS p/ max fitness =');
    TL(t2,[0.03 0.220 0.94 0.035],'  alpha*mean(SE) + (1-alpha)*min(SE).');
    TL(t2,[0.03 0.150 0.94 0.06],'Custo por avaliacao = Rx x Tx x Nsym chamadas SimRIS. Use Nsym baixo p/ otimizar rapido.');

    last = struct('SE',[],'SINR',[]);
    redraw();

    % ================= callbacks =================
    function setStop(), stopFlag=true; logmsg('>> PARADA solicitada'); end
    function onEnv(~,~)
        if dEnv.Value==1                      % Indoor (InH Office) -> 80x50
            area=[80 50]; tbl.Data=zeros(0,7);            % sem predios outdoor
            eLb.String=mat2str([2 2 2]); eUb.String=mat2str([78 48 3]);
        else                                  % Outdoor (UMi) -> 300x200
            area=[300 200]; tbl.Data=B0;
            eLb.String=mat2str(Lb0); eUb.String=mat2str(Ub0);
        end
        redraw();
    end
    function toggleOpt(~,~)
        v=dOpt.Value;                         % 1 Nenhum, 2 FPA, 3 AG, 4 Sequencial
        pFPA.Visible='off'; pAG.Visible='off'; pSeq.Visible='off';
        if v==2, pFPA.Visible='on';
        elseif v==3, pAG.Visible='on';
        elseif v==4, pSeq.Visible='on'; updateNpts(); end
    end
    function updateNpts()
        try
            Lb_=str2num(eLb.String); Ub_=str2num(eUb.String); %#ok<ST2NM>
            st=str2double(eStep.String);
            nx=numel(Lb_(1):st:Ub_(1)); ny=numel(Lb_(2):st:Ub_(2));
            if logical(cFixZ.Value), nz=1; else, nz=numel(Lb_(3):st:Ub_(3)); end
            lblNpts.String=sprintf('Grid: %d x %d x %d = %d pontos\n(passo %.1fm, %.0fm x %.0fm x %.0fm)', ...
                nx,ny,nz,nx*ny*nz,st,Ub_(1)-Lb_(1),Ub_(2)-Lb_(2),Ub_(3)-Lb_(3));
        catch, lblNpts.String=''; end
    end
    function addRow(~,~), D=tbl.Data; D(end+1,:)=[100 130 80 120 0 30 40]; tbl.Data=D; end
    function delRow(~,~), D=tbl.Data; if size(D,1)>=1, D(end,:)=[]; end, tbl.Data=D; end

    function loadCSV(~,~)
        [fn,pp]=uigetfile({'*.csv','CSV (*.csv)'},'Selecione CSV de nos (type,x,y,z)',here);
        if isequal(fn,0), return; end
        try
            T=readtable(fullfile(pp,fn));
            vn=lower(string(T.Properties.VariableNames));
            cx=findcol(vn,["x","posx","x_m"]); cy=findcol(vn,["y","posy","y_m"]); cz=findcol(vn,["z","posz","z_m"]);
            XY=[T{:,cx} T{:,cy}];
            if cz>0, Z=T{:,cz}; else, Z=nan(size(XY,1),1); end
            ct=findcol(vn,["type","tipo"]);
            if ct>0
                ty=lower(string(T{:,ct}));
                isTx=startsWith(ty,"tx"); isRx=startsWith(ty,"rx"); isRIS=startsWith(ty,"ris");
                Ztx=Z; Ztx(isnan(Ztx))=10; Zrx=Z; Zrx(isnan(Zrx))=1.5; Zri=Z; Zri(isnan(Zri))=30;
                TxL=[XY(isTx,:) Ztx(isTx)]; RxL=[XY(isRx,:) Zrx(isRx)];
                if any(isRIS)                              % RIS do CSV (usa a 1a linha RIS)
                    Ri=[XY(isRIS,:) Zri(isRIS)]; RIS=Ri(1,:); lblRIS.String=mat2str(round(RIS,2));
                end
                isOB=startsWith(ty,"obst");                % obstaculos (AABB) do CSV
                cxn=findcol(vn,["xmin"]); cxx=findcol(vn,["xmax"]);
                cyn=findcol(vn,["ymin"]); cyx=findcol(vn,["ymax"]);
                czn=findcol(vn,["zmin"]); czx=findcol(vn,["zmax"]);
                cat=findcol(vn,["att_db","attdb","att"]);
                if any(isOB) && all([cxn cxx cyn cyx czn czx cat]>0)
                    B=[T{isOB,cxn} T{isOB,cxx} T{isOB,cyn} T{isOB,cyx} T{isOB,czn} T{isOB,czx} T{isOB,cat}];
                    tbl.Data=B;
                end
            else
                Zr=Z; Zr(isnan(Zr))=1.5; RxL=[XY Zr];   % sem coluna type -> tudo Rx
            end
            if isempty(TxL), TxL=[0 100 10]; end          % default se CSV nao trouxe Tx
            if isempty(RxL), RxL=[85 95 1.5]; end
            lblNos.String=sprintf('Tx:%d Rx:%d',size(TxL,1),size(RxL,1));
            last.SE=[]; redraw();
            logmsg(sprintf('CSV carregado: %d Tx, %d Rx, %d Obst',size(TxL,1),size(RxL,1),size(tbl.Data,1)));
        catch ME
            txtOut.String=['Erro lendo CSV: ' ME.message];
            logmsg(['Erro CSV: ' ME.message]);
        end
    end

    function genRandom(~,~)
        nTx=max(1,round(str2double(eGTx.String))); nRx=max(1,round(str2double(eGRx.String)));
        B=tbl.Data; mg=5;
        xmx=max([area(1),B(:,2)']); ymx=max([area(2),B(:,4)']);
        TxL=randNodes(nTx,10.0,xmx,ymx,mg,B,true);    % Tx fora dos predios
        RxL=randNodes(nRx,1.5, xmx,ymx,mg,B,true);    % Rx no chao, fora dos predios (rua)
        zmaxB=max([0;B(:,6)]);                          % topo do predio mais alto
        RIS=round([mg+(xmx-2*mg)*rand, mg+(ymx-2*mg)*rand, zmaxB+5+10*rand]);  % inteiro
        tries=0;                                        % garante RIS fora de predio
        while inFootprint(RIS(1),RIS(2),RIS(3),B) && tries<500
            RIS=round([mg+(xmx-2*mg)*rand, mg+(ymx-2*mg)*rand, zmaxB+5+10*rand]); tries=tries+1;
        end
        lblRIS.String=mat2str(round(RIS,2));
        writeNodesCSV(fullfile(here,'nos_random.csv'),TxL,RxL,RIS,B);
        lblNos.String=sprintf('Tx:%d Rx:%d',nTx,nRx);
        last.SE=[]; redraw();                      % nos novos -> SE obsoleto
        logmsg(sprintf('Gerado %d Tx, %d Rx, RIS [%d %d %d]',nTx,nRx,RIS(1),RIS(2),RIS(3)));
        s=txtOut.String; if ischar(s), s={s}; end
        s{end+1}=sprintf('Gerado: nos_random.csv (Tx %d, Rx %d, RIS [%.0f %.0f %.0f])',nTx,nRx,RIS); txtOut.String=s;
    end

    function p=getParams()
        p.Env=dEnv.Value; scv=[1 2]; p.Sc=scv(dSc.Value);
        frv=[28 73]; p.Fr=frv(dFr.Value); p.AT=dAT.Value;
        p.N=round(str2double(eN.String)); p.Nsym=round(str2double(eNsym.String));
        p.Nt=1; p.Nr=1;                    % SISO fixo (Nt=Nr=1)
        p.par=logical(cPar.Value)||logical(cPar2.Value);  % multi-processo (parfor) - qualquer aba
        p.noRIS=logical(cNoRIS.Value);     % baseline: so link direto Tx-Rx
        p.reps=max(1,round(str2double(eReps.String)));  % repeticoes do RUN (media+-std)
        p.det=(dMod.Value==2);             % canal deterministico (sem fading)
    end

    function syncPar(src,~)           % espelha checkbox parfor entre abas Cenario/Otimizacao
        v=logical(src.Value); cPar.Value=v; cPar2.Value=v;
    end

    function drawScene()
        % desenha topologia. Linhas RIS->Rx coloridas por SE (se houver run);
        % senao por oclusao (vermelho=bloqueado).
        B=tbl.Data;
        cla(ax); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        allp=[TxL;RxL;RIS];
        xmx=max([area(1),B(:,2)',allp(:,1)']); ymx=max([area(2),B(:,4)',allp(:,2)']);
        zmx=max([10,B(:,6)',allp(:,3)'])+5;
        patch(ax,[0 xmx xmx 0],[0 0 ymx ymx],[0 0 0 0],[0.93 0.93 0.88],'FaceAlpha',0.4,'EdgeColor','none');
        for k=1:size(B,1), drawbox(ax,B(k,1),B(k,2),B(k,3),B(k,4),B(k,5),B(k,6),B(k,7),zmx); end
        noRIS = logical(cNoRIS.Value);              % baseline: links diretos Tx-Rx
        % links Tx<->RIS (cor = oclusao) -- ocultos no modo sem RIS
        if ~noRIS
            for j=1:size(TxL,1)
                o=occlusao_att_dB(TxL(j,:),RIS,B);
                plot3(ax,[TxL(j,1) RIS(1)],[TxL(j,2) RIS(2)],[TxL(j,3) RIS(3)],'-','LineWidth',1.6,'Color',pick(o,[0 .45 .74]));
            end
        end
        % links p/ Rx (cor = SE se disponivel). com RIS: RIS->Rx. sem RIS: Tx->Rx.
        useSE = ~isempty(last.SE) && numel(last.SE)==size(RxL,1);
        if useSE
            se=last.SE; smin=min(se); smax=max(se); if smax<=smin, smax=smin+1e-6; end
            cmap=turbo(256);
        end
        for i=1:size(RxL,1)
            if useSE
                tt=min(max((last.SE(i)-smin)/(smax-smin),0),1);
                col=cmap(round(tt*255)+1,:); lw=2.0;
                ocol=col;
            else
                col=[.85 .33 .1]; lw=1.2; ocol=[];   % ocol vazio -> cor por oclusao
            end
            if noRIS                                 % link direto de cada Tx ao Rx
                for j=1:size(TxL,1)
                    if isempty(ocol)
                        o=occlusao_att_dB(TxL(j,:),RxL(i,:),B); c=pick(o,col);
                    else, c=ocol; end
                    plot3(ax,[TxL(j,1) RxL(i,1)],[TxL(j,2) RxL(i,2)],[TxL(j,3) RxL(i,3)],'-','LineWidth',lw,'Color',c);
                end
            else                                     % link refletido RIS->Rx
                if isempty(ocol)
                    o=occlusao_att_dB(RIS,RxL(i,:),B); col=pick(o,col);
                end
                plot3(ax,[RIS(1) RxL(i,1)],[RIS(2) RxL(i,2)],[RIS(3) RxL(i,3)],'-','LineWidth',lw,'Color',col);
            end
        end
        plot3(ax,TxL(:,1),TxL(:,2),TxL(:,3),'^','MarkerFaceColor',[0 .45 .74],'MarkerEdgeColor','k','MarkerSize',11);
        plot3(ax,RxL(:,1),RxL(:,2),RxL(:,3),'o','MarkerFaceColor',[.85 .33 .1],'MarkerEdgeColor','k','MarkerSize',7);
        if noRIS, risFace=[.6 .6 .6]; risTxt=' RIS (off)'; else, risFace=[.47 .67 .19]; risTxt=' RIS'; end
        plot3(ax,RIS(1),RIS(2),RIS(3),'s','MarkerFaceColor',risFace,'MarkerEdgeColor','k','MarkerSize',15);
        text(ax,RIS(1),RIS(2),RIS(3)+3,risTxt,'FontWeight','bold');
        for j=1:size(TxL,1), text(ax,TxL(j,1),TxL(j,2),TxL(j,3)+3,sprintf(' Tx%d',j),'FontWeight','bold','FontSize',8); end
        xlabel(ax,'x (m)'); ylabel(ax,'y (m)'); zlabel(ax,'z (m)');
        xlim(ax,[0 xmx]); ylim(ax,[0 ymx]); zlim(ax,[0 zmx]);
        daspect(ax,[1 1 0.25]); view(ax,40,25); rotate3d(ax,'on');
        if useSE                                    % colorbar de SE
            colormap(ax,turbo);
            try, clim(ax,[smin smax]); catch, caxis(ax,[smin smax]); end %#ok<CAXIS>
            cb=colorbar(ax); cb.Label.String='SE (bps/Hz)';
        else
            colorbar(ax,'off');
        end
    end

    function redraw(~,~)
        B=tbl.Data;
        drawScene();
        nbad=0;
        for q=1:size(TxL,1), nbad=nbad+inFootprint(TxL(q,1),TxL(q,2),TxL(q,3),B); end
        for q=1:size(RxL,1), nbad=nbad+inFootprint(RxL(q,1),RxL(q,2),RxL(q,3),B); end
        nbad=nbad+inFootprint(RIS(1),RIS(2),RIS(3),B);
        msg={sprintf('Tx: %d   Rx: %d   Obst: %d',size(TxL,1),size(RxL,1),size(B,1))};
        if nbad>0, msg{end+1}=sprintf('AVISO: %d no(s) DENTRO de predio!',nbad);
        else, msg{end+1}='Ajuste e clique RUN SimRIS.'; end
        txtOut.String=msg;
    end

    function [SE,SINRdB,seMedRep]=computeSE(ris,B,p)
        K=size(RxL,1); M=size(TxL,1); N_=p.N; Rxs=RxL; Txs=TxL; sn=SNR_lin;
        noRIS_=isfield(p,'noRIS')&&p.noRIS;
        pEnv=p.Env; pSc=p.Sc; pFr=p.Fr; pAT=p.AT; pNt=p.Nt; pNr=p.Nr;

        if isfield(p,'det') && p.det
            % === Canal Deterministico: perda de percurso media, sem fading ===
            % Calculo unico por (Tx,Rx,RIS) — sem loop MC, sem variancia.
            SE=zeros(K,1); SINRdB=zeros(K,1); seMedRep=0;
            for ii=1:K
                aG_=10^(-occlusao_att_dB(ris,Rxs(ii,:),B)/20);
                pot=zeros(M,1);
                Hc=complex(zeros(N_,M)); Gvc=complex(zeros(N_,M)); Dc=complex(zeros(M,1));
                for jj=1:M
                    aH_=10^(-occlusao_att_dB(Txs(jj,:),ris,B)/20);
                    aD_=10^(-occlusao_att_dB(Txs(jj,:),Rxs(ii,:),B)/20);
                    [hd,gd,dd]=SimRIS_v18_det(pEnv,pSc,pFr,pAT,N_,pNt,pNr,Txs(jj,:),Rxs(ii,:),ris);
                    Hv=hd(:)*aH_; Gv=gd(:)*aG_; Dk=dd*aD_;
                    if noRIS_, pot(jj)=abs(Dk)^2;
                    else, pot(jj)=(sum(abs(Hv).*abs(Gv))+abs(Dk))^2; end
                    Hc(:,jj)=Hv; Gvc(:,jj)=Gv; Dc(jj)=Dk;
                end
                [psig,js]=max(pot); pint=0;
                if M>1
                    if ~noRIS_
                        ph_js=exp(1j*(angle(Dc(js))-angle(Hc(:,js))-angle(Gvc(:,js))));
                    end
                    for jj=1:M
                        if jj==js, continue; end
                        if noRIS_, Cint=Dc(jj);
                        else, Cint=sum(Gvc(:,jj).*ph_js.*Hc(:,jj))+Dc(jj); end
                        pint=pint+abs(Cint)^2;
                    end
                end
                SINR=(sn*psig)/(sn*pint+1);
                SE(ii)=log2(1+SINR); SINRdB(ii)=10*log10(max(SINR,1e-12));
            end
            return;
        end

        % === Canal Estocástico (Monte Carlo) ===
        % Fase 1: parfor flat sobre K*M*R tarefas, cada uma chamando
        %   SimRIS_v18_batch que gera Nsym amostras em batch (geometria 1x).
        %   Reduz chamadas de K*M*Ns*R para K*M*R (fator Nsym a menos).
        % Fase 2: SINR/SE sem diag(N×N): usa algebra real para servidor
        %   e produto elemento-a-elemento para interferencia.
        Ns=p.Nsym; R=max(1,p.reps);
        usepar=isfield(p,'par')&&p.par;

        % Atenuacoes geometricas (deterministicas)
        aG_=zeros(K,1); aH_=zeros(M,K); aD_=zeros(M,K);
        for ii=1:K
            aG_(ii)=10^(-occlusao_att_dB(ris,Rxs(ii,:),B)/20);
            for jj=1:M
                aH_(jj,ii)=10^(-occlusao_att_dB(Txs(jj,:),ris,B)/20);
                aD_(jj,ii)=10^(-occlusao_att_dB(Txs(jj,:),Rxs(ii,:),B)/20);
            end
        end

        % Expande para K*M*R tarefas (sliced variables no parfor).
        % Mapeamento: idx = (r-1)*K*M + (j-1)*K + i
        total=K*M*R;
        Tx_exp=zeros(total,3); Rx_exp=zeros(total,3);
        aH_exp=zeros(total,1); aG_exp=zeros(total,1); aD_exp=zeros(total,1);
        for idx_=1:total
            r1=mod(idx_-1,K*M); jj=floor(r1/K)+1; ii=mod(r1,K)+1;
            Tx_exp(idx_,:)=Txs(jj,:); Rx_exp(idx_,:)=Rxs(ii,:);
            aH_exp(idx_)=aH_(jj,ii); aG_exp(idx_)=aG_(ii); aD_exp(idx_)=aD_(jj,ii);
        end

        % --- Fase 1: K*M*R chamadas a SimRIS_v18_batch, cada retornando Ns amostras ---
        H_all=complex(zeros(N_,Ns,total));
        G_all=complex(zeros(N_,Ns,total));
        D_all=complex(zeros(Ns,total));
        if usepar
            parfor idx_=1:total
                [Hb,Gb,Db]=SimRIS_v18_batch(pEnv,pSc,pFr,pAT,N_,pNt,pNr,Tx_exp(idx_,:),Rx_exp(idx_,:),ris,Ns);
                H_all(:,:,idx_)=Hb*aH_exp(idx_);
                G_all(:,:,idx_)=Gb*aG_exp(idx_);
                D_all(:,idx_)=Db*aD_exp(idx_);
            end
        else
            for idx_=1:total
                [Hb,Gb,Db]=SimRIS_v18_batch(pEnv,pSc,pFr,pAT,N_,pNt,pNr,Tx_exp(idx_,:),Rx_exp(idx_,:),ris,Ns);
                H_all(:,:,idx_)=Hb*aH_exp(idx_);
                G_all(:,:,idx_)=Gb*aG_exp(idx_);
                D_all(:,idx_)=Db*aD_exp(idx_);
            end
        end

        % --- Fase 2: SINR/SE por (rep, UE, simbolo) ---
        % Servidor: |C|^2 = (sum(|H|.*|G|) + |D|)^2  [fase otima, aritmetica real]
        % Interferencia: sum(G_j .* ph_js .* H_j) + D_j  [sem matriz diag N×N]
        SEr=zeros(K,R); SIr=zeros(K,R);
        KM=K*M;
        for rr=1:R
            rep_base=(rr-1)*KM;
            for ii=1:K
                accSE=0; accSINR=0;
                for s=1:Ns
                    pot=zeros(M,1);
                    Hc=complex(zeros(N_,M)); Gvc=complex(zeros(N_,M)); Dc=complex(zeros(M,1));
                    for jj=1:M
                        ch=rep_base+(jj-1)*K+ii;
                        Hv=H_all(:,s,ch); Gv=G_all(:,s,ch); Dk=D_all(s,ch);
                        if noRIS_, pot(jj)=abs(Dk)^2;
                        else, pot(jj)=(sum(abs(Hv).*abs(Gv))+abs(Dk))^2; end
                        Hc(:,jj)=Hv; Gvc(:,jj)=Gv; Dc(jj)=Dk;
                    end
                    [psig,js]=max(pot); pint=0;
                    if M>1
                        if ~noRIS_
                            ph_js=exp(1j*(angle(Dc(js))-angle(Hc(:,js))-angle(Gvc(:,js))));
                        end
                        for jj=1:M
                            if jj==js, continue; end
                            if noRIS_, Cint=Dc(jj);
                            else, Cint=sum(Gvc(:,jj).*ph_js.*Hc(:,jj))+Dc(jj); end
                            pint=pint+abs(Cint)^2;
                        end
                    end
                    SINR=(sn*psig)/(sn*pint+1);
                    accSE=accSE+log2(1+SINR); accSINR=accSINR+SINR;
                end
                SEr(ii,rr)=accSE/Ns; SIr(ii,rr)=10*log10(accSINR/Ns);
            end
        end
        SE=mean(SEr,2); SINRdB=mean(SIr,2);
        seMedRep=mean(SEr,1)';  % R×1: media de SE por rep (para std entre reps)
    end

    function fobj=makeFitness(B,p,alpha,intFlag)
        fobj=@(ris) fitfun(ris,B,p,alpha,intFlag);
        function fv=fitfun(ris,B,p,alpha,intFlag)
            if intFlag, ris=round(ris); end          % busca em coordenadas inteiras
            if inFootprint(ris(1),ris(2),ris(3),B)   % RIS nao pode ficar dentro de predio
                fv=-1e6; return;                     % penalidade -> otimizador evita
            end
            SE=computeSE(ris,B,p);
            fv=alpha*mean(SE)+(1-alpha)*min(SE);
        end
    end

    function optimizeRIS(~,~)
        B=tbl.Data; p=getParams();
        if mod(sqrt(p.N),1)~=0, txtOut.String='Erro: N deve ser quadrado perfeito.'; return; end
        opt=dOpt.Value; if opt==1, txtOut.String='Escolha FPA, AG ou Sequencial.'; return; end
        alpha=str2double(eAlpha.String); Lb=str2num(eLb.String); Ub=str2num(eUb.String); %#ok<ST2NM>
        intFlag=logical(cInt.Value);
        if logical(cFixZ.Value)                  % altura z fixa: otimiza so x,y
            zf=str2double(eFixZ.String);
            if intFlag, zf=round(zf); end
            Lb(3)=zf; Ub(3)=zf; RIS(3)=zf;       % trava z em zf (init+clamp mantem)
            logmsg(sprintf('Altura RIS fixa em z=%g m',zf));
        end
        fobj=makeFitness(B,p,alpha,intFlag);
        % --- rastro da RIS em tempo de execucao ---
        stopFlag=false;                            % zera pedido de parada
        last.SE=[]; redraw(); traj=zeros(0,3);
        if opt==2, nome='FPA'; logmsg('Iniciando FPA...');
        elseif opt==3, nome='AG'; logmsg('Iniciando AG...');
        else, nome='Seq'; logmsg('Iniciando busca sequencial...'); end
        % --- CSV em tempo real (nome com data/hora de inicio) ---
        csvfile='';
        if logical(cSave.Value)
            K=size(RxL,1);
            csvfile=fullfile(here,sprintf('otim_%s_%s.csv',nome,datestr(now,'yyyymmdd_HHMMSS')));
            fid=fopen(csvfile,'w');
            hdr='datahora,iter,fitness,SE_med,SE_min,SE_5,RISx,RISy,RISz';
            for q=1:K, hdr=[hdr sprintf(',se_%d',q)]; end %#ok<AGROW>
            fprintf(fid,'%s\n',hdr); fclose(fid);
            logmsg(['CSV: ' csvfile]);
        end
        cb=@progress;
        txtOut.String='Otimizando RIS... (rastro roxo na topologia)'; drawnow; t0=tic;
        if opt==2   % FPA
            par=struct('n',round(str2double(eFn.String)),'p',str2double(eFp.String), ...
                'iter',round(str2double(eFit.String)),'gamma',str2double(eFg.String),'beta',str2double(eFb.String));
            [best,fbest,conv]=runFPA(fobj,Lb,Ub,par,cb);
        elseif opt==3  % AG
            par=struct('pop',round(str2double(eAp.String)),'ger',round(str2double(eAg.String)), ...
                'pc',str2double(eApc.String),'pm',str2double(eApm.String),'elite',round(str2double(eAe.String)));
            [best,fbest,conv]=runGA(fobj,Lb,Ub,par,cb);
        else           % Sequencial (Grid)
            step_v=max(0.5,str2double(eStep.String));
            usepar_=isfield(p,'par')&&p.par;
            [best,fbest,conv]=runSequential(fobj,Lb,Ub,step_v,usepar_,cb);
        end
        if intFlag, best=round(best); end
        RIS=best; lblRIS.String=mat2str(round(RIS,2));
        title(ax,sprintf('%s: RIS otima [%.1f %.1f %.1f] fit=%.3f',nome,best(1),best(2),best(3),fbest));
        out={};
        out{end+1}=sprintf('=== %s OK (%.1fs) ===',nome,toc(t0));
        out{end+1}=sprintf('RIS otima: [%.2f %.2f %.2f]',best(1),best(2),best(3));
        out{end+1}=sprintf('fitness  : %.4f bps/Hz',fbest);
        out{end+1}=sprintf('conv: %.3f -> %.3f (%d passos)',conv(1),conv(end),numel(conv));
        if ~isempty(csvfile), out{end+1}=['CSV: ' csvfile]; end
        out{end+1}='Clique RUN SimRIS p/ estatisticas completas.';
        txtOut.String=out;
        logmsg(sprintf('%s fim: RIS [%.1f %.1f %.1f] fit %.3f',nome,best(1),best(2),best(3),fbest));

        function stop=progress(it,bestpos,fb)
            if intFlag, bestpos=round(bestpos); end
            traj(end+1,:)=bestpos; %#ok<AGROW>
            RIS=bestpos;                           % move a RIS (estado)
            [se,~]=computeSE(bestpos,tbl.Data,p);  % SE por UE na posicao atual
            last.SE=se; lblRIS.String=mat2str(round(RIS,2));
            drawScene();                           % RIS verde move + arestas por SE
            hold(ax,'on');                         % sobrepoe rastro
            plot3(ax,traj(:,1),traj(:,2),traj(:,3),'-','Color',[0.6 0 0.6],'LineWidth',1.6);
            plot3(ax,bestpos(1),bestpos(2),bestpos(3),'p','MarkerFaceColor',[1 1 0],'MarkerEdgeColor','k','MarkerSize',16);
            title(ax,sprintf('%s iter %d | RIS [%.1f %.1f %.1f] | fit %.3f',nome,it,bestpos(1),bestpos(2),bestpos(3),fb));
            logmsg(sprintf('%s it %3d | fit %.3f | SEmed %.2f | RIS [%.0f %.0f %.0f]',nome,it,fb,mean(se),bestpos(1),bestpos(2),bestpos(3)));
            if ~isempty(csvfile)                   % grava linha no CSV em tempo real
                fid=fopen(csvfile,'a');
                if fid>0
                    fprintf(fid,'%s,%d,%.6f,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f', ...
                        datestr(now,'yyyy-mm-dd HH:MM:SS'),it,fb,mean(se),min(se),pct(se,5),bestpos(1),bestpos(2),bestpos(3));
                    fprintf(fid,',%.6f',se); fprintf(fid,'\n'); fclose(fid);
                end
            end
            drawnow;                               % full -> processa PARAR e atualiza topologia
            stop=stopFlag;                         % sinaliza parada ao otimizador
        end
    end

    function runSim(~,~)
        B=tbl.Data; p=getParams();
        if mod(sqrt(p.N),1)~=0, txtOut.String='Erro: N deve ser quadrado perfeito.'; return; end
        M=size(TxL,1); K=size(RxL,1); R=p.reps;
        txtOut.String=sprintf('Rodando: %d Rx x %d Tx x Nsym=%d x Reps=%d ...',K,M,p.Nsym,R); drawnow;
        t0=tic;
        % computeSE absorve Reps internamente e usa SimRIS_v18_batch
        [SE,SINRdB,seMedRep]=computeSE(RIS,B,p);
        last.SE=SE; last.SINR=SINRdB;
        drawScene();                              % recolore linhas RIS->Rx por SE
        logmsg(sprintf('RUN: SEmed %.3f  SE5%% %.3f  (%d Rx, %d reps)',mean(SE),pct(SE,5),K,R));
        out={};
        out{end+1}=sprintf('=== RUN OK (%.1fs) ===',toc(t0));
        out{end+1}=sprintf('Tx=%d Rx=%d N=%d Nsym=%d Reps=%d',M,K,p.N,p.Nsym,R);
        out{end+1}='';
        out{end+1}=sprintf('SINR medio : %7.2f dB',mean(SINRdB));
        out{end+1}=sprintf('SINR 5%%    : %7.2f dB',pct(SINRdB,5));
        out{end+1}=sprintf('SE medio   : %7.4f bps/Hz',mean(SE));
        if R>1
            out{end+1}=sprintf('  +-std(reps): %7.4f  [%.4f, %.4f]',std(seMedRep),min(seMedRep),max(seMedRep));
        end
        out{end+1}=sprintf('SE 5%%      : %7.4f bps/Hz',pct(SE,5));
        out{end+1}=sprintf('SE mediana : %7.4f bps/Hz',median(SE));
        out{end+1}=sprintf('SE min/max : %.3f / %.3f',min(SE),max(SE));
        txtOut.String=out;
    end

    function saveMat(~,~)
        if isempty(last.SE), txtOut.String='Rode SimRIS antes de salvar.'; return; end
        fn=fullfile(here,'resultado_multi.mat'); SE=last.SE; SINRdB=last.SINR;
        Tx=TxL; Rx=RxL; save(fn,'SE','SINRdB','Tx','Rx'); %#ok<NASGU>
        s=txtOut.String; if ischar(s), s={s}; end; s{end+1}=['Salvo: ' fn]; txtOut.String=s;
    end

    function logmsg(s)
        logLines{end+1}=s; %#ok<AGROW>
        if numel(logLines)>9, logLines=logLines(end-8:end); end
        logBox.String=[{'LOG:'}, logLines];
    end
    function c=pick(o,cdef), if o>0, c=[0.85 0 0]; else, c=cdef; end, end
end

% ===== config embutida (defaults outdoor UMi) =====
function cfg = outdoor_config()
    cfg = struct();
    att = 40;
    cfg.blockers = [
         60  90  20 100 0 35 att;
        210 240 100 180 0 35 att;
        120 150  30  80 0 30 att;
        120 150 120 170 0 40 att;
         90 110 120 160 0 25 att;
        190 215  20  70 0 30 att];
    cfg.SNR_lin = 10^((30-(-80))/10);    % Pt=30dBm, Pn=-80dBm
    cfg.Lb = [10 10 20];                  % caixa de busca RIS (UAV)
    cfg.Ub = [290 190 35];
    cfg.alpha = 0.7;                      % fitness = alpha*mean + (1-alpha)*min
end

% ===== oclusao por predios (slab segmento-AABB) =====
function att_dB = occlusao_att_dB(P1, P2, blockers)
    att_dB = 0;
    if isempty(blockers); return; end
    d = P2 - P1; EPS = 1e-9;
    for k = 1:size(blockers,1)
        bmin = blockers(k, [1 3 5]); bmax = blockers(k, [2 4 6]);
        tmin = 0; tmax = 1; hit = true;
        for ax = 1:3
            if abs(d(ax)) < EPS
                if P1(ax) < bmin(ax) || P1(ax) > bmax(ax), hit = false; break; end
            else
                t1 = (bmin(ax) - P1(ax)) / d(ax); t2 = (bmax(ax) - P1(ax)) / d(ax);
                if t1 > t2, tmp = t1; t1 = t2; t2 = tmp; end
                tmin = max(tmin, t1); tmax = min(tmax, t2);
                if tmin > tmax, hit = false; break; end
            end
        end
        if hit && (tmax - tmin) > 1e-9, att_dB = att_dB + blockers(k, 7); end
    end
end

% ===== avaliacao de 1 UE (escopo de arquivo p/ permitir parfor) =====
function [se,sinrdb]=oneUE(Rx,TxL,ris,B,p,SNR_lin)
    M=size(TxL,1); a=@(dB)10^(-dB/20); aG=a(occlusao_att_dB(ris,Rx,B));
    accSE=0; accSINR=0; ok=0;
    for r=1:p.Nsym
        pot=zeros(M,1); Hc=cell(M,1); Gc=cell(M,1); Dc=zeros(M,1); thc=cell(M,1);
        for j=1:M
            Tx=TxL(j,:); aH=a(occlusao_att_dB(Tx,ris,B)); aD=a(occlusao_att_dB(Tx,Rx,B));
            [h,g,d]=SimRIS_v18(p.Env,p.Sc,p.Fr,p.AT,p.N,p.Nt,p.Nr,Tx,Rx,ris);
            Hv=h(:)*aH; Gv=g(:)*aG; Dk=d*aD;
            th=angle(Dk)-(angle(Hv)+angle(Gv));
            if isfield(p,'noRIS') && p.noRIS
                C=Dk;                                  % sem RIS: so link direto
            else
                C=transpose(Gv)*diag(exp(1j*th))*Hv+Dk;
            end
            Hc{j}=Hv; Gc{j}=Gv; Dc(j)=Dk; thc{j}=th; pot(j)=abs(C)^2;
        end
        [psig,js]=max(pot); pint=0;
        for j=1:M
            if j==js, continue; end
            if isfield(p,'noRIS') && p.noRIS
                Cint=Dc(j);                            % sem RIS: interf. so direta
            else
                Cint=transpose(Gc{j})*diag(exp(1j*thc{js}))*Hc{j}+Dc(j);
            end
            pint=pint+abs(Cint)^2;
        end
        SINR=(SNR_lin*psig)/(SNR_lin*pint+1);
        accSE=accSE+log2(1+SINR); accSINR=accSINR+SINR; ok=ok+1;
    end
    se=accSE/ok; sinrdb=10*log10(accSINR/ok);
end

% ===== otimizadores =====
function [best,fbest,conv]=runSequential(fobj,Lb,Ub,step,usepar,cb)
% Busca exaustiva em grade: avalia todos os pontos [Lb:step:Ub].
% Garante o otimo global na grade. Parfor: avaliacao em bloco (sem progresso).
% Serial: atualiza display a cada melhoria ou a cada n/200 avaliacoes.
    xv=Lb(1):step:Ub(1); yv=Lb(2):step:Ub(2); zv=Lb(3):step:Ub(3);
    [XX,YY,ZZ]=ndgrid(xv,yv,zv);
    pts=round([XX(:) YY(:) ZZ(:)]);   % posicoes na grade (inteiros)
    n=size(pts,1);
    fbest=-inf; best=pts(1,:); conv=zeros(n,1);
    if usepar
        fits=-inf(n,1);
        parfor i=1:n, fits(i)=fobj(pts(i,:)); end %#ok<PFUNK>
        [fbest,ibest]=max(fits); best=pts(ibest,:);
        m=fits(1); for i=1:n, if fits(i)>m, m=fits(i); end; conv(i)=m; end
    else
        freq=max(1,floor(n/200));
        for i=1:n
            f=fobj(pts(i,:));
            if f>fbest, fbest=f; best=pts(i,:); end
            conv(i)=fbest;
            if ~isempty(cb)&&(mod(i,freq)==0||i==n)
                if cb(i,best,fbest), conv=conv(1:i); return; end
            end
        end
    end
    if ~isempty(cb), cb(n,best,fbest); end
end

function [best,fbest,conv]=runFPA(fobj,Lb,Ub,par,cb)
% Flower Pollination Algorithm (Yang). Maximiza fobj na caixa [Lb,Ub].
    if nargin<5, cb=[]; end
    n=par.n; p=par.p; N=par.iter; gstep=par.gamma; beta=par.beta; d=numel(Lb);
    Sol=zeros(n,d);
    for i=1:n, Sol(i,:)=clampv(Lb+rand(1,d).*(Ub-Lb),Lb,Ub); end
    Fit=zeros(n,1); for i=1:n, Fit(i)=fobj(Sol(i,:)); drawnow limitrate; end
    [fbest,I]=max(Fit); best=Sol(I,:);
    sigma=(gamma(1+beta)*sin(pi*beta/2)/(gamma((1+beta)/2)*beta*2^((beta-1)/2)))^(1/beta);
    conv=zeros(N,1);
    for t=1:N
        for i=1:n
            if rand>p
                u=randn(1,d)*sigma; v=randn(1,d); Lf=u./abs(v).^(1/beta);
                cand=Sol(i,:)+gstep*Lf.*(Sol(i,:)-best);
            else
                JK=randperm(n); cand=Sol(i,:)+rand*(Sol(JK(1),:)-Sol(JK(2),:));
            end
            cand=clampv(cand,Lb,Ub); fc=fobj(cand);
            if fc>=Fit(i), Sol(i,:)=cand; Fit(i)=fc; if fc>fbest, fbest=fc; best=cand; end, end
            drawnow limitrate;
        end
        conv(t)=fbest;
        if ~isempty(cb), if cb(t,best,fbest), conv=conv(1:t); break; end, end
    end
end
function [best,fbest,conv]=runGA(fobj,Lb,Ub,par,cb)
% Algoritmo Genetico real-coded: torneio + crossover blend + mutacao gaussiana + elitismo.
    if nargin<5, cb=[]; end
    pop=par.pop; G=par.ger; pc=par.pc; pm=par.pm; el=max(0,par.elite); d=numel(Lb);
    X=zeros(pop,d); for i=1:pop, X(i,:)=Lb+rand(1,d).*(Ub-Lb); end
    F=zeros(pop,1); for i=1:pop, F(i)=fobj(X(i,:)); drawnow limitrate; end
    conv=zeros(G,1); best=X(1,:); fbest=-inf;
    for g=1:G
        [F,idx]=sort(F,'descend'); X=X(idx,:);
        newX=X(1:min(el,pop),:);
        while size(newX,1)<pop
            p1=tourn(X,F); p2=tourn(X,F);
            if rand<pc, aa=rand(1,d); c1=aa.*p1+(1-aa).*p2; c2=aa.*p2+(1-aa).*p1; else, c1=p1; c2=p2; end
            newX=[newX; clampv(gmut(c1,Lb,Ub,pm),Lb,Ub)]; %#ok<AGROW>
            if size(newX,1)<pop, newX=[newX; clampv(gmut(c2,Lb,Ub,pm),Lb,Ub)]; end %#ok<AGROW>
        end
        X=newX(1:pop,:);
        for i=1:pop, F(i)=fobj(X(i,:)); drawnow limitrate; end
        [fb,I]=max(F); if fb>fbest, fbest=fb; best=X(I,:); end
        conv(g)=fbest;
        if ~isempty(cb), if cb(g,best,fbest), conv=conv(1:g); break; end, end
    end
end
function p=tourn(X,F)
    n=size(X,1); a=randi(n); b=randi(n);
    if F(a)>=F(b), p=X(a,:); else, p=X(b,:); end
end
function c=gmut(c,Lb,Ub,pm)
    for k=1:numel(c), if rand<pm, c(k)=c(k)+0.1*(Ub(k)-Lb(k))*randn; end, end
end
function s=clampv(s,Lb,Ub), s=max(s,Lb); s=min(s,Ub); end

% ===== helpers =====
function P=randNodes(n,zval,xmx,ymx,mg,B,avoidBld)
    P=zeros(n,3); k=0; tries=0;
    while k<n && tries<n*200
        tries=tries+1;
        x=round(mg+(xmx-2*mg)*rand); y=round(mg+(ymx-2*mg)*rand);   % posicoes inteiras
        if avoidBld && inFootprint(x,y,zval,B), continue; end
        k=k+1; P(k,:)=[x y zval];
    end
    if k<n, P(k+1:end,:)=[]; end
end
function tf=inFootprint(x,y,z,B)
    tf=false;
    for k=1:size(B,1)
        if x>=B(k,1)&&x<=B(k,2)&&y>=B(k,3)&&y<=B(k,4)&&z>=B(k,5)&&z<=B(k,6), tf=true; return; end
    end
end
function writeNodesCSV(fn,TxL,RxL,RIS,B)
    if nargin<5, B=zeros(0,7); end
    fid=fopen(fn,'w');
    fprintf(fid,'type,x,y,z,xmin,xmax,ymin,ymax,zmin,zmax,att_dB\n');
    if nargin>=4 && ~isempty(RIS)
        fprintf(fid,'RIS,%.4f,%.4f,%.4f,,,,,,,\n',RIS(1),RIS(2),RIS(3));
    end
    for j=1:size(TxL,1), fprintf(fid,'Tx,%.4f,%.4f,%.4f,,,,,,,\n',TxL(j,1),TxL(j,2),TxL(j,3)); end
    for i=1:size(RxL,1), fprintf(fid,'Rx,%.4f,%.4f,%.4f,,,,,,,\n',RxL(i,1),RxL(i,2),RxL(i,3)); end
    for k=1:size(B,1)   % obstaculos (AABB): so a caixa nas colunas extras (x,y,z vazios)
        fprintf(fid,'OBST,,,,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n', ...
            B(k,1),B(k,2),B(k,3),B(k,4),B(k,5),B(k,6),B(k,7));
    end
    fclose(fid);
end
function c=findcol(vn,opts)
    c=0; for k=1:numel(opts), idx=find(vn==opts(k),1); if ~isempty(idx), c=idx; return; end, end
end
function q=pct(x,p)
    x=sort(x(:)); n=numel(x); if n==1, q=x; return; end
    pos=min(max(p/100*n+0.5,1),n); lo=floor(pos); hi=ceil(pos); q=x(lo)+(pos-lo)*(x(hi)-x(lo));
end
function drawbox(ax,x1,x2,y1,y2,z1,z2,attdB,zref)
    c=min([0.5 0.5 0.6]+0.15*(z2-z1)/max(zref,1),1);
    V=[x1 y1 z1;x2 y1 z1;x2 y2 z1;x1 y2 z1;x1 y1 z2;x2 y1 z2;x2 y2 z2;x1 y2 z2];
    Fc=[1 2 3 4;5 6 7 8;1 2 6 5;2 3 7 6;3 4 8 7;4 1 5 8];
    patch(ax,'Vertices',V,'Faces',Fc,'FaceColor',c,'FaceAlpha',0.35,'EdgeColor',[.3 .3 .3]);
    text(ax,(x1+x2)/2,(y1+y2)/2,z2+1,sprintf('%.0fdB',attdB),'HorizontalAlignment','center','FontSize',7,'Color',[.2 .2 .2]);
end

% ===== engine SimRIS_v18 (canal RIS UMi/InH) =====
function [h,g,h_SISO]=SimRIS_v18(Environment,Scenario,Frequency,ArrayType,N,Nt,Nr,Tx_xyz,Rx_xyz,RIS_xyz)

lambda=(3*10^8)/(Frequency*10^9);  % Wavelength
k=2*pi/lambda;                     % Wavenumber
dis=lambda/2;                      

x_Tx=Tx_xyz(1);y_Tx=Tx_xyz(2);z_Tx=Tx_xyz(3);
x_Rx=Rx_xyz(1);y_Rx=Rx_xyz(2);z_Rx=Rx_xyz(3);
x_RIS=RIS_xyz(1);y_RIS=RIS_xyz(2);z_RIS=RIS_xyz(3);

if mod(sqrt(N),1)~=0
    error('N should be an integer power of 2')
end

if Environment==1 % INDOORS
    n_NLOS=3.19;          
    sigma_NLOS=8.29;      
    b_NLOS=0.06;          
    f0=24.2;              
    n_LOS=1.73;           
    sigma_LOS=3.02;       
    b_LOS=0;              
else  % OUTDOORS
    n_NLOS=3.19;          
    sigma_NLOS=8.2;       
    b_NLOS=0;             
    f0=24.2;              
    n_LOS=1.98;          
    sigma_LOS=3.1;       
    b_LOS=0;             
end

if Frequency==28
    lambda_p=1.8;
elseif Frequency==73
    lambda_p=1.9;
end

q=0.285;
Gain=pi;

d_T_RIS = norm(Tx_xyz-RIS_xyz);    

if Environment==1
    if z_RIS<z_Tx   
        if d_T_RIS<= 1.2
            p_LOS=1;
        elseif 1.2<d_T_RIS && d_T_RIS<6.5
            p_LOS=exp(-(d_T_RIS-1.2)/4.7);
        else
            p_LOS=0.32*exp(-(d_T_RIS-6.5)/32.6);
        end
        I_LOS=randsrc(1,1,[1,0;p_LOS 1-p_LOS]);
    elseif z_RIS>=z_Tx 
        I_LOS=1;
    end
elseif Environment==2
    p_LOS=min([20/d_T_RIS,1])*(1-exp(-d_T_RIS/39)) + exp(-d_T_RIS/39);
    I_LOS=randsrc(1,1,[1,0;p_LOS 1-p_LOS]);
end

if I_LOS==1
    if Scenario==1   
        I_phi=sign(x_RIS-x_Tx);
        phi_T_RIS_LOS = I_phi* atand ( abs( x_RIS-x_Tx) / abs(y_RIS-y_Tx) );
        I_theta=sign(z_Tx-z_RIS);
        theta_T_RIS_LOS=I_theta * asind ( abs (z_RIS-z_Tx )/ d_T_RIS );
        I_phi_Tx=sign(y_Tx-y_RIS);
        phi_Tx_LOS = I_phi_Tx* atand ( abs( y_Tx-y_RIS) / abs(x_Tx-x_RIS) );
        I_theta_Tx=sign(z_Tx-z_RIS);
        theta_Tx_LOS=I_theta_Tx * asind ( abs (z_RIS-z_Tx )/ d_T_RIS );
    elseif Scenario==2 
        I_phi=sign(y_Tx-y_RIS);   
        phi_T_RIS_LOS  = I_phi* atand ( abs(y_RIS-y_Tx ) / abs(  x_RIS-x_Tx ) );
        I_theta=sign(z_Tx-z_RIS);  
        theta_T_RIS_LOS=I_theta * asind ( abs (z_RIS-z_Tx )/ d_T_RIS );
        I_phi_Tx=sign(y_Tx-y_RIS);
        phi_Tx_LOS = I_phi_Tx* atand ( abs( y_RIS-y_Tx) / abs(x_RIS-x_Tx) );
        I_theta_Tx=sign(z_RIS-z_Tx);
        theta_Tx_LOS=I_theta_Tx * asind ( abs (z_RIS-z_Tx )/ d_T_RIS );
    end
    
    array_RIS_LOS=zeros(1,N);
    counter3=1;
    for x=0:sqrt(N)-1
        for y=0:sqrt(N)-1
            array_RIS_LOS(counter3)=exp(1i*k*dis*(x*sind(theta_T_RIS_LOS) + y*sind(phi_T_RIS_LOS)*cosd(theta_T_RIS_LOS) )) ;
            counter3=counter3+1;
        end
    end
    
    if ArrayType == 1
    array_Tx_LOS = zeros(1,Nt);
    counter3=1;
        for x=0:Nt-1
            array_Tx_LOS(counter3)=exp(1i*k*dis*(x*sind(phi_Tx_LOS)*cosd(theta_Tx_LOS) )) ;
            counter3=counter3+1;
        end
    elseif ArrayType == 2
       counter3=1;
        for x=0:sqrt(Nt)-1
            for y=0:sqrt(Nt)-1
            array_Tx_LOS(counter3)=exp(1i*k*dis*(x*sind(phi_Tx_LOS)*cosd(theta_Tx_LOS) + y*sind(theta_Tx_LOS))) ;
            counter3=counter3+1;
            end
        end   
    end
            
    L_dB_LOS=-20*log10(4*pi/lambda) - 10*n_LOS*(1+b_LOS*((Frequency-f0)/f0))*log10(d_T_RIS)- randn*sigma_LOS;
    L_LOS=10^(L_dB_LOS/10);
    h_LOS=sqrt(L_LOS)*transpose(array_RIS_LOS)*array_Tx_LOS*exp(1i*rand*2*pi)*sqrt(Gain*(cosd(theta_T_RIS_LOS))^(2*q));
else
    h_LOS=0;
end

for generate=1:100  
     C=max([1, round(lambda_p)]);  
    S=randi(30,1,C);
    phi_Tx=[ ];
    theta_Tx=[ ];
    phi_av=zeros(1,C);
    theta_av=zeros(1,C);
    for counter=1:C
        phi_av(counter)  = rand*180-90;     
        theta_av(counter)= rand*90-45;      
        phi_Tx   = [phi_Tx,log(rand(1,S(counter))./rand(1,S(counter)))*sqrt(25/2) + phi_av(counter)];
        theta_Tx = [theta_Tx,log(rand(1,S(counter))./rand(1,S(counter)))*sqrt(25/2) + theta_av(counter)];
    end
    a_c=1+rand(1,C)*(d_T_RIS-1);    
    if Environment ==1
        dim=[75,50,3.5];                  
        Coordinates=zeros(C,3);          
        Coordinates2=zeros(sum(S),3);    
        for counter=1:C
            Coordinates(counter,:)=[x_Tx + a_c(counter)*cosd(theta_av(counter))*cosd(phi_av(counter)),...
                y_Tx - a_c(counter)*cosd(theta_av(counter))*sind(phi_av(counter)),...
                z_Tx + a_c(counter)*sind(theta_av(counter))] ;
            while Coordinates(counter,3)>dim(3) || Coordinates(counter,3)<0 ||  Coordinates(counter,2)>dim(2) ||  Coordinates(counter,2)<0  ||  Coordinates(counter,1)>dim(1) ||  Coordinates(counter,1)<0
                a_c(counter)=    0.8*a_c(counter)  ;     
                Coordinates(counter,:)=[x_Tx + a_c(counter)*cosd(theta_av(counter))*cosd(phi_av(counter)),...
                    y_Tx - a_c(counter)*cosd(theta_av(counter))*sind(phi_av(counter)),...
                    z_Tx + a_c(counter)*sind(theta_av(counter))] ;
            end
        end
    elseif Environment==2 
        Coordinates=zeros(C,3);          
        Coordinates2=zeros(sum(S),3);    
        for counter=1:C
            Coordinates(counter,:)=[x_Tx + a_c(counter)*cosd(theta_av(counter))*cosd(phi_av(counter)),...
                y_Tx - a_c(counter)*cosd(theta_av(counter))*sind(phi_av(counter)),...
                z_Tx + a_c(counter)*sind(theta_av(counter))] ;
            while  Coordinates(counter,3)<0    
                a_c(counter)=    0.8*a_c(counter)  ;     
                Coordinates(counter,:)=[x_Tx + a_c(counter)*cosd(theta_av(counter))*cosd(phi_av(counter)),...
                    y_Tx - a_c(counter)*cosd(theta_av(counter))*sind(phi_av(counter)),...
                    z_Tx + a_c(counter)*sind(theta_av(counter))] ;
            end
        end
    end
    a_c_rep=[];
    for counter3=1:C
        a_c_rep=[a_c_rep,repmat(a_c(counter3),1,S(counter3))];
    end
    for counter2=1:sum(S)
        Coordinates2(counter2,:)=[x_Tx + a_c_rep(counter2)*cosd(theta_Tx(counter2))*cosd(phi_Tx(counter2)),...
            y_Tx - a_c_rep(counter2)*cosd(theta_Tx(counter2))*sind(phi_Tx(counter2)),...
            z_Tx + a_c_rep(counter2)*sind(theta_Tx(counter2))] ;
    end
    
    if Environment==1
        ignore=[];
        for counter2=1:sum(S)
            if Coordinates2(counter2,3)>dim(3) || Coordinates2(counter2,3)<0 ||  Coordinates2(counter2,2)>dim(2) ||  Coordinates2(counter2,2)<0  ||  Coordinates2(counter2,1)>dim(1) ||  Coordinates2(counter2,1)<0
                ignore=[ignore,counter2];   
            end
        end
        indices=setdiff(1:sum(S),ignore);    
        M_new=length(indices);               
        
    elseif Environment==2
        ignore=[];
        for counter2=1:sum(S)
            if  Coordinates2(counter2,3)<0   
                ignore=[ignore,counter2];   
            end
        end
        indices=setdiff(1:sum(S),ignore);    
        M_new=length(indices);               
    end
    
    if M_new>0 
        break  
    end
end  

phi_cs_RIS=zeros(1,sum(S));
theta_cs_RIS=zeros(1,sum(S));
phi_Tx_cs=zeros(1,sum(S));
theta_Tx_cs=zeros(1,sum(S));
b_cs=zeros(1,sum(S));
d_cs=zeros(1,sum(S));

if Scenario==1   
    for counter2=indices
        b_cs(counter2)=norm(RIS_xyz-Coordinates2(counter2,:));   
        d_cs(counter2)=a_c_rep(counter2)+b_cs(counter2);         
        I_phi=sign(x_RIS-Coordinates2(counter2,1));
        phi_cs_RIS(counter2)  = I_phi* atand ( abs( x_RIS-Coordinates2(counter2,1)) / abs(y_RIS-Coordinates2(counter2,2)) );
        I_theta=sign(Coordinates2(counter2,3)-z_RIS);
        theta_cs_RIS(counter2)=I_theta * asind ( abs (z_RIS-Coordinates2(counter2,3) )/ b_cs(counter2) );
        I_phi_Tx_cs=sign(y_Tx-Coordinates2(counter2,2));
        phi_Tx_cs(counter2) = I_phi_Tx_cs* atand ( abs( Coordinates2(counter2,2)-y_Tx) / abs(Coordinates2(counter2,1)-x_Tx) );
        I_theta_Tx_cs=sign(Coordinates2(counter2,3)-z_Tx);
        theta_Tx_cs(counter2)=I_theta_Tx_cs * asind ( abs (Coordinates2(counter2,3)-z_Tx )/ a_c_rep(counter2) );
    end
elseif Scenario==2 
    for counter2=indices
        b_cs(counter2)=norm(RIS_xyz-Coordinates2(counter2,:));   
        d_cs(counter2)=a_c_rep(counter2)+b_cs(counter2);         
        I_phi=sign(Coordinates2(counter2,2)-y_RIS);   
        phi_cs_RIS(counter2)  = I_phi* atand ( abs(y_RIS-Coordinates2(counter2,2) ) / abs(  x_RIS-Coordinates2(counter2,1) ) );
        I_theta=sign(Coordinates2(counter2,3)-z_RIS);  
        theta_cs_RIS(counter2)=I_theta * asind ( abs (z_RIS-Coordinates2(counter2,3) )/ b_cs(counter2) );
        I_phi_Tx_cs=sign(y_Tx-Coordinates2(counter2,2));
        phi_Tx_cs(counter2) = I_phi_Tx_cs* atand ( abs( Coordinates2(counter2,2)-y_Tx) / abs(Coordinates2(counter2,1)-x_Tx) );
        I_theta_Tx_cs=sign(Coordinates2(counter2,3)-z_Tx);
        theta_Tx_cs(counter2)=I_theta_Tx_cs * asind ( abs (Coordinates2(counter2,3)-z_Tx )/ a_c_rep(counter2) );
    end
end

array_cs_RIS=zeros(sum(S),N);
for counter2=indices
    counter3=1;
    for x=0:sqrt(N)-1
        for y=0:sqrt(N)-1
            array_cs_RIS(counter2,counter3)=exp(1i*k*dis*(x*sind(theta_cs_RIS(counter2)) + y*sind(phi_cs_RIS(counter2))*cosd(theta_cs_RIS(counter2)) )) ;
            counter3=counter3+1;
        end
    end
end

array_Tx_cs=zeros(sum(S),Nt);

if ArrayType == 1
for counter2 = indices
    counter3=1;
    for x=0:Nt-1
        array_Tx_cs(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_Tx_cs(counter2))*cosd(theta_Tx_cs(counter2)) )) ;
        counter3=counter3+1;
    end
end
elseif ArrayType == 2
for counter2 = indices
    counter3=1;
    for x=0:sqrt(Nt)-1
        for y = 0:sqrt(Nt)-1
        array_Tx_cs(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_Tx_cs(counter2))*cosd(theta_Tx_cs(counter2)) + y*sind(theta_Tx_cs(counter2)) )) ;
        counter3=counter3+1;
        end
    end
end
end

h_NLOS=zeros(N,Nt);
beta=zeros(1,sum(S)); 
shadow=beta;          
for counter2=indices
    X_sigma=randn*sigma_NLOS;
    Lcs_dB=-20*log10(4*pi/lambda) - 10*n_NLOS*(1+b_NLOS*((Frequency-f0)/f0))*log10(d_cs(counter2))- X_sigma;
    Lcs=10^(Lcs_dB/10);
    beta(counter2)=((randn+1i*randn)./sqrt(2));  
    shadow(counter2)=X_sigma;                    
    h_NLOS = h_NLOS + beta(counter2)*sqrt(Gain*(cosd(theta_cs_RIS(counter2)))^(2*q))*sqrt(Lcs)*transpose(array_cs_RIS(counter2,:))*array_Tx_cs(counter2,:);  
end
h_NLOS=h_NLOS.*sqrt(1/M_new);  
h=h_NLOS+h_LOS; 

if Environment==1   
    d_RIS_R=norm(RIS_xyz-Rx_xyz);
    I_theta=sign(z_Rx - z_RIS);
    theta_Rx_RIS=I_theta * asind( abs(z_Rx-z_RIS)/d_RIS_R ); 
    if Scenario==1
        I_phi=sign(x_RIS - x_Rx);
        phi_Rx_RIS=I_phi * atand( abs(x_Rx-x_RIS)/ abs(y_Rx-y_RIS) ); 
        phi_av_Rx  = rand*180-90;     
        theta_av_Rx= rand*180-90;      
        phi_Rx   = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_Rx];
        theta_Rx = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_Rx];
    elseif Scenario==2
        I_phi=sign(y_Rx- y_RIS);
        phi_Rx_RIS=I_phi * atand( abs(y_Rx-y_RIS)/ abs(x_Rx-x_RIS) );
        phi_av_Rx  = rand*180-90;     
        theta_av_Rx= rand*180-90;      
        phi_Rx   = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_Rx];
        theta_Rx = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_Rx];
    end
    array_2=zeros(1,N);
    counter3=1;
    for x=0:sqrt(N)-1
        for y=0:sqrt(N)-1
            array_2(counter3)=exp(1i*k*dis*(x*sind(theta_Rx_RIS) + y*sind(phi_Rx_RIS)*cosd(theta_Rx_RIS) )) ;
            counter3=counter3+1;         
        end
    end
    
    array_Rx = zeros(1,Nr);
    if ArrayType == 1
    counter3=1;
    for x=0:Nr-1
        array_Rx(counter3)=exp(1i*k*dis*(x*sind(phi_Rx)*cosd(theta_Rx) )) ;
        counter3=counter3+1;
    end
    elseif ArrayType == 2
    counter3=1;
    for x=0:sqrt(Nr)-1
        for y=0:sqrt(Nr)-1
        array_Rx(counter3)=exp(1i*k*dis*(x*sind(phi_Rx)*cosd(theta_Rx)+y*sind(theta_Rx)  )) ;
        counter3=counter3+1;
        end
    end
    end
    L_dB_LOS_2=-20*log10(4*pi/lambda) - 10*n_LOS*(1+b_LOS*((Frequency-f0)/f0))*log10(d_RIS_R)- randn*sigma_LOS;
    L_LOS_2=10^(L_dB_LOS_2/10);
    g=sqrt(Gain*(cosd(theta_Rx_RIS))^(2*q))*sqrt(L_LOS_2)*transpose(array_2)*array_Rx*exp(1i*rand*2*pi);   
    
elseif Environment==2
    d_RIS_R=norm(RIS_xyz-Rx_xyz);
    p_LOS_2=min([20/d_RIS_R,1])*(1-exp(-d_RIS_R/39)) + exp(-d_RIS_R/39);
    I_LOS_2=randsrc(1,1,[1,0;p_LOS_2 1-p_LOS_2]);
    if I_LOS_2==1
        if Scenario==1   
            I_phi=sign(x_RIS-x_Rx);
            phi_RIS_R_LOS = I_phi* atand ( abs( x_RIS-x_Rx) / abs(y_RIS-y_Rx) );
            I_theta=sign(z_Rx-z_RIS);
            theta_RIS_R_LOS=I_theta * asind ( abs (z_RIS-z_Rx )/ d_RIS_R );
            phi_av_Rx_LOS = rand*180-90;     
            theta_av_Rx_LOS= rand*180-90;      
            phi_Rx_LOS   = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_Rx_LOS];
            theta_Rx_LOS = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_Rx_LOS];
        elseif Scenario==2 
            I_phi=sign(y_Rx-y_RIS);   
            phi_RIS_R_LOS  = I_phi* atand ( abs(y_RIS-y_Rx ) / abs(  x_RIS-x_Rx ) );
            I_theta=sign(z_Rx-z_RIS);  
            theta_RIS_R_LOS=I_theta * asind ( abs (z_RIS-z_Rx )/ d_RIS_R );
            phi_av_Rx_LOS = rand*180-90;     
            theta_av_Rx_LOS= rand*180-90;      
            phi_Rx_LOS   = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_Rx_LOS];
            theta_Rx_LOS = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_Rx_LOS];
        end
        array_RIS_Rx_LOS=zeros(1,N);
        array_Rx_LOS = zeros(1,Nr);
        counter3=1;
        for x=0:sqrt(N)-1
            for y=0:sqrt(N)-1
                array_RIS_Rx_LOS(counter3)=exp(1i*k*dis*(x*sind(theta_RIS_R_LOS) + y*sind(phi_RIS_R_LOS)*cosd(theta_RIS_R_LOS) )) ;
                counter3=counter3+1;              
            end
        end
        if ArrayType == 1
        counter3=1;
        for x=0:Nr-1
            array_Rx_LOS(counter3)=exp(1i*k*dis*(x*sind(phi_Rx_LOS)*cosd(theta_Rx_LOS) )) ;
            counter3=counter3+1;
        end
        elseif ArrayType == 2
        counter3=1;
        for x = 0:sqrt(Nr)-1
            for y = 0:sqrt(Nr)-1
            array_Rx_LOS(counter3)=exp(1i*k*dis*(x*sind(phi_Rx_LOS)*cosd(theta_Rx_LOS)+y*sind(theta_Rx_LOS))) ;
            counter3=counter3+1;
            end
        end
        end
        L_dB_LOS_2=-20*log10(4*pi/lambda) - 10*n_LOS*(1+b_LOS*((Frequency-f0)/f0))*log10(d_RIS_R)- randn*sigma_LOS;
        L_LOS_2=10^(L_dB_LOS_2/10);
        g_LOS=sqrt(L_LOS_2)*transpose(array_RIS_Rx_LOS)*array_Rx_LOS*exp(1i*rand*2*pi)*sqrt(Gain*(cosd(theta_RIS_R_LOS))^(2*q));
    else
        g_LOS=0;
    end
    
    for generate2=1:100  
        C_2=max([1,poissrnd_local(lambda_p)]);
        S_2=randi(30,1,C_2);
        phi_Tx_2=[ ];
        theta_Tx_2=[ ];
        phi_av_2=zeros(1,C_2);
        theta_av_2=zeros(1,C_2);
        for counter=1:C_2
            phi_av_2(counter)  = rand*90-45;   
            theta_av_2(counter)= rand*90-45; 
            phi_Tx_2   = [phi_Tx_2,  log(rand(1,S_2(counter))./rand(1,S_2(counter)))*sqrt(25/2) + phi_av_2(counter)];
            theta_Tx_2 = [theta_Tx_2,log(rand(1,S_2(counter))./rand(1,S_2(counter)))*sqrt(25/2) + theta_av_2(counter)];
        end
        a_c_2=1+rand(1,C_2)*(d_RIS_R-1);    
        Coordinates_2=zeros(C_2,3);          
        Coordinates2_2=zeros(sum(S_2),3);    
        for counter=1:C_2
            if Scenario==1       
                Coordinates_2(counter,:)=[x_RIS - a_c_2(counter)*cosd(theta_av_2(counter))*sind(phi_av_2(counter)),...
                    y_RIS - a_c_2(counter)*cosd(theta_av_2(counter))*cosd(phi_av_2(counter)),...
                    z_RIS + a_c_2(counter)*sind(theta_av_2(counter))];
            elseif Scenario==2   
                Coordinates_2(counter,:)=[x_RIS - a_c_2(counter)*cosd(theta_av_2(counter))*cosd(phi_av_2(counter)),...
                    y_RIS + a_c_2(counter)*cosd(theta_av_2(counter))*sind(phi_av_2(counter)),...
                    z_RIS + a_c_2(counter)*sind(theta_av_2(counter))];
            end
            while  Coordinates_2(counter,3)<0    
                a_c_2(counter)=    0.8*a_c_2(counter)  ;     
                if Scenario==1       
                    Coordinates_2(counter,:)=[x_RIS - a_c_2(counter)*cosd(theta_av_2(counter))*sind(phi_av_2(counter)),...
                        y_RIS - a_c_2(counter)*cosd(theta_av_2(counter))*cosd(phi_av_2(counter)),...
                        z_RIS + a_c_2(counter)*sind(theta_av_2(counter))];
                elseif Scenario==2   
                    Coordinates_2(counter,:)=[x_RIS - a_c_2(counter)*cosd(theta_av_2(counter))*cosd(phi_av_2(counter)),...
                        y_RIS + a_c_2(counter)*cosd(theta_av_2(counter))*sind(phi_av_2(counter)),...
                        z_RIS + a_c_2(counter)*sind(theta_av_2(counter))];
                end
            end
        end
        a_c_rep_2=[];
        for counter3=1:C_2
            a_c_rep_2=[a_c_rep_2,repmat(a_c_2(counter3),1,S_2(counter3))];
        end
        for counter2=1:sum(S_2)
            if Scenario==1       
                Coordinates2_2(counter2,:)=[x_RIS - a_c_rep_2(counter2)*cosd(theta_Tx_2(counter2))*sind(phi_Tx_2(counter2)),...
                    y_RIS - a_c_rep_2(counter2)*cosd(theta_Tx_2(counter2))*cosd(phi_Tx_2(counter2)),...
                    z_RIS + a_c_rep_2(counter2)*sind(theta_Tx_2(counter2))];
            elseif Scenario==2   
                Coordinates2_2(counter2,:)=[x_RIS - a_c_rep_2(counter2)*cosd(theta_Tx_2(counter2))*cosd(phi_Tx_2(counter2)),...
                    y_RIS + a_c_rep_2(counter2)*cosd(theta_Tx_2(counter2))*sind(phi_Tx_2(counter2)),...
                    z_RIS + a_c_rep_2(counter2)*sind(theta_Tx_2(counter2))];
            end
        end
        ignore_2=[];
        for counter2=1:sum(S_2)
            if  Coordinates2_2(counter2,3)<0   
                ignore_2=[ignore_2,counter2];   
            end
        end
        indices_2=setdiff(1:sum(S_2),ignore_2);    
        M_new_2=length(indices_2);               
        if M_new_2>0 
            break  
        end
    end  
    array_2=zeros(sum(S_2),N);
    for counter2=indices_2
        counter3=1;
        for x=0:sqrt(N)-1
            for y=0:sqrt(N)-1
                array_2(counter2,counter3)=exp(1i*k*dis*(x*sind(theta_Tx_2(counter2)) + y*sind(phi_Tx_2(counter2))*cosd(theta_Tx_2(counter2)) )) ;
                counter3=counter3+1;
            end
        end
    end
    b_cs_2=zeros(1,sum(S_2));
    d_cs_2=zeros(1,sum(S_2));
    phi_cs_Rx = zeros(1,sum(S_2));
    theta_cs_Rx = zeros(1,sum(S_2));
    for counter2=indices_2
        b_cs_2(counter2)=norm(Rx_xyz-Coordinates2_2(counter2,:));   
        d_cs_2(counter2)=a_c_rep_2(counter2)+b_cs_2(counter2);         
        if Scenario == 1
        phi_av_Rx_NLOS(counter2)  = rand*180-90;     
        theta_av_Rx_NLOS(counter2)= rand*180-90;      
        phi_cs_Rx(counter2)   = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_Rx_NLOS(counter2)];
        theta_cs_Rx(counter2) = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_Rx_NLOS(counter2)];
        elseif Scenario ==2
        phi_av_Rx_NLOS(counter2)  = rand*180-90;     
        theta_av_Rx_NLOS(counter2)= rand*180-90;      
        phi_cs_Rx(counter2)   = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_Rx_NLOS(counter2) ];
        theta_cs_Rx(counter2)  = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_Rx_NLOS(counter2) ];
        end
    end
    array_Rx_cs=zeros(sum(S_2),Nr);
    if ArrayType == 1
    for counter2 = indices_2
        counter3=1;
        for x=0:Nr-1
            array_Rx_cs(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Rx(counter2))*cosd(theta_cs_Rx(counter2)) )) ;
            counter3=counter3+1;
        end
    end
    elseif ArrayType == 2
      for counter2 = indices_2
        counter3=1;
        for x=0:sqrt(Nr)-1
            for  y=0:sqrt(Nr)-1
            array_Rx_cs(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Rx(counter2))*cosd(theta_cs_Rx(counter2))+y*sind(theta_cs_Rx(counter2)) )) ;
            counter3=counter3+1;
            end
        end
    end  
    end
    g_NLOS=zeros(N,Nr);
    for counter2=indices_2
        X_sigma_2=randn*sigma_NLOS;
        Lcs_dB_2=-20*log10(4*pi/lambda) - 10*n_NLOS*(1+b_NLOS*((Frequency-f0)/f0))*log10(d_cs_2(counter2))- X_sigma_2;
        Lcs_2=10^(Lcs_dB_2/10);
        beta_2=((randn+1i*randn)./sqrt(2));
        g_NLOS = g_NLOS + beta_2*sqrt(Lcs_2)*sqrt(Gain*(cosd(theta_Tx_2(counter2)))^(2*q))*transpose(array_2(counter2,:))*array_Rx_cs(counter2,:);   
    end
    g_NLOS=g_NLOS.*sqrt(1/M_new_2);  
    g=g_NLOS+g_LOS;
end

if Environment==1  
    d_T_R=norm(Tx_xyz-Rx_xyz);
    d_cs_tilde=zeros(1,sum(S));
    h_SISO_NLOS=0;
    for counter2=indices
        d_cs_tilde(counter2) = a_c_rep(counter2) + norm(Coordinates2(counter2,:)- Rx_xyz);
        I_phi_Tx_cs_SISO=sign(y_Tx-Coordinates2(counter2,2));
        phi_Tx_cs_SISO(counter2) = I_phi_Tx_cs_SISO* atand ( abs( Coordinates2(counter2,2)-y_Tx) / abs(Coordinates2(counter2,1)-x_Tx) );
        I_theta_Tx_cs_SISO=sign(Coordinates2(counter2,3)-z_Tx);
        theta_Tx_cs_SISO(counter2)=I_theta_Tx_cs_SISO * asind ( abs (Coordinates2(counter2,3)-z_Tx )/ a_c_rep(counter2) );
        phi_av_SISO(counter2)  = rand*180-90;     
        theta_av_SISO(counter2)= rand*180-90;      
        phi_cs_Rx_SISO(counter2)   = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_SISO(counter2)];
        theta_cs_Rx_SISO(counter2) = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_SISO(counter2)];
        if ArrayType == 1
        counter3=1;
        for x=0:Nr-1
            array_Rx_cs_SISO(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Rx_SISO(counter2))*cosd(theta_cs_Rx_SISO(counter2)) )) ;
            counter3=counter3+1;
        end
        counter3=1;
        for x=0:Nt-1
            array_Tx_cs_SISO(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_Tx_cs_SISO(counter2))*cosd(theta_Tx_cs_SISO(counter2)) )) ;
            counter3=counter3+1;
        end
        elseif ArrayType ==2
             counter3=1;
        for x=0:sqrt(Nr)-1
            for y=0:sqrt(Nr)-1
            array_Rx_cs_SISO(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Rx_SISO(counter2))*cosd(theta_cs_Rx_SISO(counter2))+y*sind(theta_cs_Rx_SISO(counter2)) )) ;
            counter3=counter3+1;
            end
        end
        counter3=1;
        for x=0:sqrt(Nt)-1
            for y=0:sqrt(Nt)-1
            array_Tx_cs_SISO(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_Tx_cs_SISO(counter2))*cosd(theta_Tx_cs_SISO(counter2))+y*sind(theta_Tx_cs_SISO(counter2))  )) ;
            counter3=counter3+1;
            end
        end
        end
        Lcs_dB_SISO=-20*log10(4*pi/lambda) - 10*n_NLOS*(1+b_NLOS*((Frequency-f0)/f0))*log10(d_cs_tilde(counter2))- shadow(counter2);
        Lcs_SISO=10^(Lcs_dB_SISO/10);
        eta=k* ( norm(Coordinates2(counter2,:)- RIS_xyz) -  norm(Coordinates2(counter2,:)- Rx_xyz));
        h_SISO_NLOS = h_SISO_NLOS + beta(counter2)*exp(1i*eta)*sqrt(Lcs_SISO)*transpose(array_Rx_cs_SISO(counter2,:))*array_Tx_cs_SISO(counter2,:);
    end
    h_SISO_NLOS=h_SISO_NLOS.*sqrt(1/M_new);  
    if z_RIS >= z_Tx
        if d_T_R<= 1.2
            p_LOS_3=1;
        elseif 1.2<d_T_R && d_T_R<6.5
            p_LOS_3=exp(-(d_T_R-1.2)/4.7);
        else
            p_LOS_3=0.32*exp(-(d_T_R-6.5)/32.6);
        end
        I_LOS_3=randsrc(1,1,[1,0;p_LOS_3 1-p_LOS_3]);
    elseif z_RIS < z_Tx  
        I_LOS_3=I_LOS;
    end
    if I_LOS_3==1
        L_SISO_LOS_dB=-20*log10(4*pi/lambda) - 10*n_LOS*(1+b_LOS*((Frequency-f0)/f0))*log10(d_T_R)- randn*sigma_LOS;
        L_SISO_LOS=10^(L_SISO_LOS_dB/10);
        I_phi_Tx_SISO=sign(y_Tx-y_Rx);
        phi_Tx_SISO = I_phi_Tx_SISO* atand ( abs( y_Tx-y_Rx) / abs(x_Tx-x_Rx) );
        I_theta_Tx_SISO=sign(z_Rx-z_Tx);
        theta_Tx_SISO= I_theta_Tx_SISO* atand ( abs( z_Rx-z_Tx) / abs(d_T_R) );
        phi_av_SISO_LOS = rand*180-90;     
        theta_av_SISO_LOS= rand*180-90;      
        phi_Rx_SISO  = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_SISO_LOS];
        theta_Rx_SISO= [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_SISO_LOS];
        if ArrayType == 1
        counter3=1;
        for x=0:Nt-1
            array_Tx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Tx_SISO)*cosd(theta_Tx_SISO) )) ;
            counter3=counter3+1;
        end
        counter3=1;
        for x=0:Nr-1
            array_Rx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Rx_SISO)*cosd(theta_Rx_SISO) )) ;
            counter3=counter3+1;
        end
        elseif ArrayType == 2
        counter3=1;
        for x=0:sqrt(Nt)-1
            for y=0:sqrt(Nt)-1
            array_Tx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Tx_SISO)*cosd(theta_Tx_SISO)+y*sind(theta_Tx_SISO)  )) ;
            counter3=counter3+1;
            end
        end
        counter3=1;
        for x=0:sqrt(Nr)-1
            for y=0:sqrt(Nr)-1
            array_Rx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Rx_SISO)*cosd(theta_Rx_SISO) +y*sind(theta_Rx_SISO))) ;
            counter3=counter3+1;
            end
        end    
        end
        h_SISO_LOS= sqrt(L_SISO_LOS)*exp(1i*rand*2*pi)*transpose(array_Rx_SISO)*array_Tx_SISO;
    else
        h_SISO_LOS=0;
    end
    h_SISO=h_SISO_NLOS + h_SISO_LOS; 
elseif Environment==2 
    d_T_R=norm(Tx_xyz-Rx_xyz);
    p_LOS_3=min([20/d_T_R,1])*(1-exp(-d_T_R/39)) + exp(-d_T_R/39);
    I_LOS_3=randsrc(1,1,[1,0;p_LOS_3 1-p_LOS_3]);
    if I_LOS_3==1
        L_SISO_LOS_dB=-20*log10(4*pi/lambda) - 10*n_LOS*(1+b_LOS*((Frequency-f0)/f0))*log10(d_T_R)- randn*sigma_LOS;
        L_SISO_LOS=10^(L_SISO_LOS_dB/10);
        I_phi_Tx_SISO=sign(y_Tx-y_Rx);
        phi_Tx_SISO = I_phi_Tx_SISO* atand ( abs( y_Tx-y_Rx) / abs(x_Tx-x_Rx) );
        I_theta_Tx_SISO=sign(z_Rx-z_Tx);
        theta_Tx_SISO= I_theta_Tx_SISO* atand ( abs( z_Rx-z_Tx) / abs(d_T_R) );
        phi_av_SISO_LOS = rand*180-90;     
        theta_av_SISO_LOS= rand*180-90;      
        phi_Rx_SISO  = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_SISO_LOS];
        theta_Rx_SISO= [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_SISO_LOS];
        if ArrayType == 1
        counter3=1;
        for x=0:Nt-1
            array_Tx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Tx_SISO)*cosd(theta_Tx_SISO) )) ;
            counter3=counter3+1;
        end
        counter3=1;
        for x=0:Nr-1
            array_Rx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Rx_SISO)*cosd(theta_Rx_SISO) )) ;
            counter3=counter3+1;
        end
        elseif ArrayType == 2
         counter3=1;
        for x=0:sqrt(Nt)-1
            for y=0:sqrt(Nt)-1
            array_Tx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Tx_SISO)*cosd(theta_Tx_SISO)+y*sind(theta_Tx_SISO) )) ;
            counter3=counter3+1;
            end
        end
        counter3=1;
        for x=0:sqrt(Nr)-1
            for y=0:sqrt(Nr)-1
            array_Rx_SISO(counter3)=exp(1i*k*dis*(x*sind(phi_Rx_SISO)*cosd(theta_Rx_SISO)+y*sind(theta_Rx_SISO) )) ;
            counter3=counter3+1;
            end
        end   
        end
        h_SISO_LOS= sqrt(L_SISO_LOS)*exp(1i*rand*2*pi)*transpose(array_Rx_SISO)*array_Tx_SISO;;   
    else
        h_SISO_LOS=0;
    end
    for generate3=1:100  
        C_3=max([1,poissrnd_local(lambda_p)]);  
        S_3=randi(30,1,C_3);
        phi_Tx_3=[ ];
        theta_Tx_3=[ ];
        phi_av_3=zeros(1,C_3);
        theta_av_3=zeros(1,C_3);
        for counter=1:C_3
            phi_av_3(counter)  = rand*180-90;   
            theta_av_3(counter)= rand*90-45; 
            phi_Tx_3   = [phi_Tx_3,  log(rand(1,S_3(counter))./rand(1,S_3(counter)))*sqrt(25/2) + phi_av_3(counter)];
            theta_Tx_3 = [theta_Tx_3,log(rand(1,S_3(counter))./rand(1,S_3(counter)))*sqrt(25/2) + theta_av_3(counter)];
        end
        a_c_3=1+rand(1,C_3)*(d_T_R-1);    
        Coordinates_3=zeros(C_3,3);          
        Coordinates2_3=zeros(sum(S_3),3);    
        for counter=1:C_3
            Coordinates_3(counter,:)=[x_Tx + a_c_3(counter)*cosd(theta_av_3(counter))*cosd(phi_av_3(counter)),...
                y_Tx - a_c_3(counter)*cosd(theta_av_3(counter))*sind(phi_av_3(counter)),...
                z_Tx + a_c_3(counter)*sind(theta_av_3(counter))] ;
            while  Coordinates_3(counter,3)<0    
                a_c_3(counter)=    0.8*a_c_3(counter)  ;     
                Coordinates_3(counter,:)=[x_Tx + a_c_3(counter)*cosd(theta_av_3(counter))*cosd(phi_av_3(counter)),...
                    y_Tx - a_c_3(counter)*cosd(theta_av_3(counter))*sind(phi_av_3(counter)),...
                    z_Tx + a_c_3(counter)*sind(theta_av_3(counter))] ;
            end
        end
        a_c_rep_3=[];
        for counter3=1:C_3
            a_c_rep_3=[a_c_rep_3,repmat(a_c_3(counter3),1,S_3(counter3))];
        end
        for counter2=1:sum(S_3)
            Coordinates2_3(counter2,:)=[x_Tx + a_c_rep_3(counter2)*cosd(theta_Tx_3(counter2))*cosd(phi_Tx_3(counter2)),...
                y_Tx - a_c_rep_3(counter2)*cosd(theta_Tx_3(counter2))*sind(phi_Tx_3(counter2)),...
                z_Tx + a_c_rep_3(counter2)*sind(theta_Tx_3(counter2))] ;
        end
        ignore_3=[];
        for counter2=1:sum(S_3)
            if  Coordinates2_3(counter2,3)<0   
                ignore_3=[ignore_3,counter2];   
            end
        end
        indices_3=setdiff(1:sum(S_3),ignore_3);    
        M_new_3=length(indices_3);               
        if M_new_3>0 
            break  
        end
    end  
    b_cs_3=zeros(1,sum(S_3));
    d_cs_3=zeros(1,sum(S_3));
    for counter2=indices_3
        b_cs_3(counter2)=norm(Tx_xyz-Coordinates2_3(counter2,:));      
        d_cs_3(counter2)=a_c_rep_3(counter2)+b_cs_3(counter2);         
            I_phi_Tx2=sign(y_Tx-Coordinates2_3(counter2,2));
            phi_cs_Tx2(counter2) = I_phi_Tx2* atand ( abs( Coordinates2_3(counter2,2)-y_Tx) / abs(Coordinates2_3(counter2,1)-x_Tx) );
            I_theta_Tx2=sign(Coordinates2_3(counter2,3)-z_Tx);
            theta_cs_Tx2(counter2)=I_theta_Tx2 * asind ( abs (Coordinates2_3(counter2,3)-z_Tx )/ a_c_rep_3(counter2) );
            phi_av_cs_Rx2(counter2) = rand*180-90;     
            theta_av_cs_Rx2(counter2) = rand*180-90;      
            phi_cs_Rx2(counter2)  = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + phi_av_cs_Rx2(counter2) ];
            theta_cs_Rx2(counter2) = [log(rand(1,1)./rand(1,1))*sqrt(25/2) + theta_av_cs_Rx2(counter2) ];
    end
    
    if ArrayType == 1
    array_Rx_cs2=zeros(sum(S_3),Nr);
    for counter2 = indices_3
        counter3=1;
        for x=0:Nr-1
            array_Rx_cs2(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Rx2(counter2))*cosd(theta_cs_Rx2(counter2)) )) ;
            counter3=counter3+1;
        end
    end
        array_Tx_cs2=zeros(sum(S_3),Nt);
    for counter2 = indices_3
        counter3=1;
        for x=0:Nt-1
            array_Tx_cs2(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Tx2(counter2))*cosd(theta_cs_Tx2(counter2)) )) ;
            counter3=counter3+1;
        end
    end
    elseif ArrayType == 2
        array_Rx_cs2=zeros(sum(S_3),Nr);
    for counter2 = indices_3
        counter3=1;
        for x=0:sqrt(Nr)-1
            for y=0:sqrt(Nr)-1 
            array_Rx_cs2(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Rx2(counter2))*cosd(theta_cs_Rx2(counter2))+y*sind(theta_cs_Rx2(counter2)) )) ;
            counter3=counter3+1;
            end
        end
    end
        array_Tx_cs2=zeros(sum(S_3),Nt);
    for counter2 = indices_3
        counter3=1;
        for x=0:sqrt(Nt)-1
            for y=0:sqrt(Nt)-1 
            array_Tx_cs2(counter2,counter3)=exp(1i*k*dis*(x*sind(phi_cs_Tx2(counter2))*cosd(theta_cs_Tx2(counter2))+y*sind(theta_cs_Tx2(counter2)) )) ;
            counter3=counter3+1;
            end
        end
    end
    end
    h_SISO_NLOS=0;
    for counter2=indices_3
        X_sigma_3=randn*sigma_NLOS;
        Lcs_dB_SISO_3=-20*log10(4*pi/lambda) - 10*n_NLOS*(1+b_NLOS*((Frequency-f0)/f0))*log10(d_cs_3(counter2))- X_sigma_3;
        Lcs_SISO_3=10^(Lcs_dB_SISO_3/10);
        h_SISO_NLOS = h_SISO_NLOS + ((randn+1i*randn)/sqrt(2))*sqrt(Lcs_SISO_3)*transpose(array_Rx_cs2(counter2,:))*array_Tx_cs2(counter2,:);
    end
    h_SISO_NLOS = h_SISO_NLOS.*sqrt(1/M_new_3);
    h_SISO = h_SISO_NLOS + h_SISO_LOS;
end
end

% -------------------------------------------------------------------------
function [H,G,D]=SimRIS_v18_batch(Environment,Scenario,Frequency,ArrayType,N,Nt,Nr,Tx_xyz,Rx_xyz,RIS_xyz,Nsym)
% Gera Nsym realizacoes independentes do canal RIS em batch.
% Geometria (clusters, angulos, steering vectors) computada UMA VEZ.
% Fast-fading (beta, shadow, fase LOS) vetorizado sobre Nsym amostras.
% Para SISO (Nt=Nr=1): arrays Tx/Rx sao escalares=1, simplificando muito.
% Retorna H (N x Nsym), G (N x Nsym), D (Nsym x 1).
% Ambiente Indoor (Env=1): fallback para Nsym chamadas de SimRIS_v18.

if Environment==1
    H=complex(zeros(N,Nsym)); G=complex(zeros(N,Nsym)); D=complex(zeros(Nsym,1));
    for ns_=1:Nsym
        [h_,g_,d_]=SimRIS_v18(Environment,Scenario,Frequency,ArrayType,N,Nt,Nr,Tx_xyz,Rx_xyz,RIS_xyz);
        H(:,ns_)=h_(:); G(:,ns_)=g_(:); D(ns_)=d_;
    end
    return;
end

% === Ambiente Outdoor (Environment=2) ===
lambda=(3e8)/(Frequency*1e9); kw=2*pi/lambda; dis_=lambda/2;
x_Tx=Tx_xyz(1);y_Tx=Tx_xyz(2);z_Tx=Tx_xyz(3);
x_Rx=Rx_xyz(1);y_Rx=Rx_xyz(2);z_Rx=Rx_xyz(3);
x_RIS=RIS_xyz(1);y_RIS=RIS_xyz(2);z_RIS=RIS_xyz(3);
sN_=sqrt(N); xv_=floor((0:N-1)/sN_); yv_=mod(0:N-1,sN_);
n_NLOS=3.19; sig_NLOS=8.2; b_NLOS=0; f0=24.2;
n_LOS=1.98; sig_LOS=3.1; b_LOS=0;
if Frequency==28, lam_p=1.8; else, lam_p=1.9; end
q_=0.285; Gn=pi;
PL0=-20*log10(4*pi/lambda);
fPL=@(d,n,b) PL0-10*n*(1+b*((Frequency-f0)/f0))*log10(max(d,1e-3));

%% === h: Tx -> RIS ===
% Decisao LOS por simbolo (vetor 1xNsym) — captura a variancia dominante de LOS/NLOS.
% Geometria dos clusters NLOS fixa por chamada (quasi-estatico); fast-fading por simbolo.
d_TR=norm(Tx_xyz-RIS_xyz);
pL=min(20/d_TR,1)*(1-exp(-d_TR/39))+exp(-d_TR/39);
los_h_=double(rand(1,Nsym)<pL);  % 1×Nsym: 1=LOS, 0=NLOS para cada simbolo
if Scenario==1
    ph_h=sign(x_RIS-x_Tx)*atand(abs(x_RIS-x_Tx)/abs(y_RIS-y_Tx));
    th_h=sign(z_Tx-z_RIS)*asind(abs(z_RIS-z_Tx)/d_TR);
else
    ph_h=sign(y_Tx-y_RIS)*atand(abs(y_RIS-y_Tx)/abs(x_RIS-x_Tx));
    th_h=sign(z_Tx-z_RIS)*asind(abs(z_RIS-z_Tx)/d_TR);
end
aRIS_h=exp(1i*kw*dis_*(xv_*sind(th_h)+yv_*sind(ph_h)*cosd(th_h))).';  % N×1
Lv_h=10.^((fPL(d_TR,n_LOS,b_LOS)-randn(1,Nsym)*sig_LOS)/10);
H_LOS=aRIS_h.*(sqrt(Lv_h).*exp(1i*rand(1,Nsym)*2*pi).*los_h_)*sqrt(Gn*(cosd(th_h))^(2*q_));
% Clusters NLOS para h
for gen_=1:100
    C_=max(1,round(lam_p)); Sv_=randi(30,1,C_);
    ph_s_=[]; th_s_=[]; phav_=zeros(1,C_); thav_=zeros(1,C_);
    for c=1:C_
        phav_(c)=rand*180-90; thav_(c)=rand*90-45;
        ph_s_=[ph_s_,log(rand(1,Sv_(c))./rand(1,Sv_(c)))*sqrt(25/2)+phav_(c)];
        th_s_=[th_s_,log(rand(1,Sv_(c))./rand(1,Sv_(c)))*sqrt(25/2)+thav_(c)];
    end
    ac_=1+rand(1,C_)*(d_TR-1); Co1_=zeros(C_,3); Co2_=zeros(sum(Sv_),3);
    for c=1:C_
        Co1_(c,:)=[x_Tx+ac_(c)*cosd(thav_(c))*cosd(phav_(c)),...
            y_Tx-ac_(c)*cosd(thav_(c))*sind(phav_(c)),...
            z_Tx+ac_(c)*sind(thav_(c))];
        while Co1_(c,3)<0
            ac_(c)=0.8*ac_(c);
            Co1_(c,:)=[x_Tx+ac_(c)*cosd(thav_(c))*cosd(phav_(c)),...
                y_Tx-ac_(c)*cosd(thav_(c))*sind(phav_(c)),...
                z_Tx+ac_(c)*sind(thav_(c))];
        end
    end
    acr_=[];for c=1:C_,acr_=[acr_,repmat(ac_(c),1,Sv_(c))];end
    for s2=1:sum(Sv_)
        Co2_(s2,:)=[x_Tx+acr_(s2)*cosd(th_s_(s2))*cosd(ph_s_(s2)),...
            y_Tx-acr_(s2)*cosd(th_s_(s2))*sind(ph_s_(s2)),...
            z_Tx+acr_(s2)*sind(th_s_(s2))];
    end
    idx_h=find(Co2_(:,3)>=0)'; Mh_=length(idx_h);
    if Mh_>0,break;end
end
bh_=zeros(1,sum(Sv_)); dh_=zeros(1,sum(Sv_));
ph_cs_h_=zeros(1,sum(Sv_)); th_cs_h_=zeros(1,sum(Sv_));
for s2=idx_h
    bh_(s2)=norm(RIS_xyz-Co2_(s2,:)); dh_(s2)=acr_(s2)+bh_(s2);
    if Scenario==1
        ph_cs_h_(s2)=sign(x_RIS-Co2_(s2,1))*atand(abs(x_RIS-Co2_(s2,1))/abs(y_RIS-Co2_(s2,2)));
        th_cs_h_(s2)=sign(Co2_(s2,3)-z_RIS)*asind(abs(z_RIS-Co2_(s2,3))/bh_(s2));
    else
        ph_cs_h_(s2)=sign(Co2_(s2,2)-y_RIS)*atand(abs(y_RIS-Co2_(s2,2))/abs(x_RIS-Co2_(s2,1)));
        th_cs_h_(s2)=sign(Co2_(s2,3)-z_RIS)*asind(abs(z_RIS-Co2_(s2,3))/bh_(s2));
    end
end
thv_h_=th_cs_h_(idx_h)'; phv_h_=ph_cs_h_(idx_h)';
Ah_=zeros(sum(Sv_),N);
Ah_(idx_h,:)=exp(1i*kw*dis_*(sind(thv_h_)*xv_+(sind(phv_h_).*cosd(thv_h_))*yv_));
dh_v_=dh_(idx_h)';
Xh_=randn(Mh_,Nsym)*sig_NLOS;
Lh_=10.^((fPL(dh_v_,n_NLOS,b_NLOS)-Xh_)/10);
bh_f_=(randn(Mh_,Nsym)+1i*randn(Mh_,Nsym))/sqrt(2);
gh_f_=sqrt(Gn*(cosd(thv_h_)).^(2*q_));
H_NLOS=Ah_(idx_h,:).'*(bh_f_.*sqrt(Lh_).*gh_f_)/sqrt(Mh_);
H=H_NLOS+H_LOS;

%% === g: RIS -> Rx ===
d_RR=norm(RIS_xyz-Rx_xyz);
pLg=min(20/d_RR,1)*(1-exp(-d_RR/39))+exp(-d_RR/39);
los_g_=double(rand(1,Nsym)<pLg);  % decisao LOS por simbolo
if Scenario==1
    ph_g=sign(x_RIS-x_Rx)*atand(abs(x_RIS-x_Rx)/abs(y_RIS-y_Rx));
    th_g=sign(z_Rx-z_RIS)*asind(abs(z_RIS-z_Rx)/d_RR);
else
    ph_g=sign(y_Rx-y_RIS)*atand(abs(y_RIS-y_Rx)/abs(x_RIS-x_Rx));
    th_g=sign(z_Rx-z_RIS)*asind(abs(z_RIS-z_Rx)/d_RR);
end
aRIS_g=exp(1i*kw*dis_*(xv_*sind(th_g)+yv_*sind(ph_g)*cosd(th_g))).';
Lv_g=10.^((fPL(d_RR,n_LOS,b_LOS)-randn(1,Nsym)*sig_LOS)/10);
G_LOS=aRIS_g.*(sqrt(Lv_g).*exp(1i*rand(1,Nsym)*2*pi).*los_g_)*sqrt(Gn*(cosd(th_g))^(2*q_));
% Clusters NLOS para g
for gen_=1:100
    C2_=max(1,poissrnd_local(lam_p)); Sv2_=randi(30,1,C2_);
    ph_s2_=[]; th_s2_=[]; phav2_=zeros(1,C2_); thav2_=zeros(1,C2_);
    for c=1:C2_
        phav2_(c)=rand*90-45; thav2_(c)=rand*90-45;
        ph_s2_=[ph_s2_,log(rand(1,Sv2_(c))./rand(1,Sv2_(c)))*sqrt(25/2)+phav2_(c)];
        th_s2_=[th_s2_,log(rand(1,Sv2_(c))./rand(1,Sv2_(c)))*sqrt(25/2)+thav2_(c)];
    end
    ac2_=1+rand(1,C2_)*(d_RR-1); Co1_2=zeros(C2_,3); Co2_2=zeros(sum(Sv2_),3);
    for c=1:C2_
        if Scenario==1
            Co1_2(c,:)=[x_RIS-ac2_(c)*cosd(thav2_(c))*sind(phav2_(c)),...
                y_RIS-ac2_(c)*cosd(thav2_(c))*cosd(phav2_(c)),...
                z_RIS+ac2_(c)*sind(thav2_(c))];
        else
            Co1_2(c,:)=[x_RIS-ac2_(c)*cosd(thav2_(c))*cosd(phav2_(c)),...
                y_RIS+ac2_(c)*cosd(thav2_(c))*sind(phav2_(c)),...
                z_RIS+ac2_(c)*sind(thav2_(c))];
        end
        while Co1_2(c,3)<0
            ac2_(c)=0.8*ac2_(c);
            if Scenario==1
                Co1_2(c,:)=[x_RIS-ac2_(c)*cosd(thav2_(c))*sind(phav2_(c)),...
                    y_RIS-ac2_(c)*cosd(thav2_(c))*cosd(phav2_(c)),...
                    z_RIS+ac2_(c)*sind(thav2_(c))];
            else
                Co1_2(c,:)=[x_RIS-ac2_(c)*cosd(thav2_(c))*cosd(phav2_(c)),...
                    y_RIS+ac2_(c)*cosd(thav2_(c))*sind(phav2_(c)),...
                    z_RIS+ac2_(c)*sind(thav2_(c))];
            end
        end
    end
    acr2_=[];for c=1:C2_,acr2_=[acr2_,repmat(ac2_(c),1,Sv2_(c))];end
    for s2=1:sum(Sv2_)
        if Scenario==1
            Co2_2(s2,:)=[x_RIS-acr2_(s2)*cosd(th_s2_(s2))*sind(ph_s2_(s2)),...
                y_RIS-acr2_(s2)*cosd(th_s2_(s2))*cosd(ph_s2_(s2)),...
                z_RIS+acr2_(s2)*sind(th_s2_(s2))];
        else
            Co2_2(s2,:)=[x_RIS-acr2_(s2)*cosd(th_s2_(s2))*cosd(ph_s2_(s2)),...
                y_RIS+acr2_(s2)*cosd(th_s2_(s2))*sind(ph_s2_(s2)),...
                z_RIS+acr2_(s2)*sind(th_s2_(s2))];
        end
    end
    idx_g=find(Co2_2(:,3)>=0)'; Mg_=length(idx_g);
    if Mg_>0,break;end
end
bg_=zeros(1,sum(Sv2_)); dg_=zeros(1,sum(Sv2_));
for s2=idx_g
    bg_(s2)=norm(Rx_xyz-Co2_2(s2,:)); dg_(s2)=acr2_(s2)+bg_(s2);
end
thv_g_=th_s2_(idx_g)'; phv_g_=ph_s2_(idx_g)';
Ag_=zeros(sum(Sv2_),N);
Ag_(idx_g,:)=exp(1i*kw*dis_*(sind(thv_g_)*xv_+(sind(phv_g_).*cosd(thv_g_))*yv_));
dg_v_=dg_(idx_g)';
Xg_=randn(Mg_,Nsym)*sig_NLOS;
Lg_=10.^((fPL(dg_v_,n_NLOS,b_NLOS)-Xg_)/10);
bg_f_=(randn(Mg_,Nsym)+1i*randn(Mg_,Nsym))/sqrt(2);
gg_f_=sqrt(Gn*(cosd(thv_g_)).^(2*q_));
G_NLOS=Ag_(idx_g,:).'*(bg_f_.*sqrt(Lg_).*gg_f_)/sqrt(Mg_);
G=G_NLOS+G_LOS;

%% === d: Tx -> Rx direto ===
d_TRx=norm(Tx_xyz-Rx_xyz);
pL3=min(20/d_TRx,1)*(1-exp(-d_TRx/39))+exp(-d_TRx/39);
los_d_=double(rand(1,Nsym)<pL3);  % decisao LOS por simbolo
Lv_d=10.^((fPL(d_TRx,n_LOS,b_LOS)-randn(1,Nsym)*sig_LOS)/10);
D_LOS=(sqrt(Lv_d).*exp(1i*rand(1,Nsym)*2*pi).*los_d_).';
for gen_=1:100
    C3_=max(1,poissrnd_local(lam_p)); Sv3_=randi(30,1,C3_);
    ph_s3_=[]; th_s3_=[]; phav3_=zeros(1,C3_); thav3_=zeros(1,C3_);
    for c=1:C3_
        phav3_(c)=rand*180-90; thav3_(c)=rand*90-45;
        ph_s3_=[ph_s3_,log(rand(1,Sv3_(c))./rand(1,Sv3_(c)))*sqrt(25/2)+phav3_(c)];
        th_s3_=[th_s3_,log(rand(1,Sv3_(c))./rand(1,Sv3_(c)))*sqrt(25/2)+thav3_(c)];
    end
    ac3_=1+rand(1,C3_)*(d_TRx-1); Co1_3=zeros(C3_,3); Co2_3=zeros(sum(Sv3_),3);
    for c=1:C3_
        Co1_3(c,:)=[x_Tx+ac3_(c)*cosd(thav3_(c))*cosd(phav3_(c)),...
            y_Tx-ac3_(c)*cosd(thav3_(c))*sind(phav3_(c)),...
            z_Tx+ac3_(c)*sind(thav3_(c))];
        while Co1_3(c,3)<0
            ac3_(c)=0.8*ac3_(c);
            Co1_3(c,:)=[x_Tx+ac3_(c)*cosd(thav3_(c))*cosd(phav3_(c)),...
                y_Tx-ac3_(c)*cosd(thav3_(c))*sind(phav3_(c)),...
                z_Tx+ac3_(c)*sind(thav3_(c))];
        end
    end
    acr3_=[];for c=1:C3_,acr3_=[acr3_,repmat(ac3_(c),1,Sv3_(c))];end
    for s2=1:sum(Sv3_)
        Co2_3(s2,:)=[x_Tx+acr3_(s2)*cosd(th_s3_(s2))*cosd(ph_s3_(s2)),...
            y_Tx-acr3_(s2)*cosd(th_s3_(s2))*sind(ph_s3_(s2)),...
            z_Tx+acr3_(s2)*sind(th_s3_(s2))];
    end
    idx_d=find(Co2_3(:,3)>=0)'; Md_=length(idx_d);
    if Md_>0,break;end
end
dd_=zeros(1,sum(Sv3_));
for s2=idx_d, dd_(s2)=acr3_(s2)+norm(Tx_xyz-Co2_3(s2,:)); end
dd_v_=dd_(idx_d)';
Xd_=randn(Md_,Nsym)*sig_NLOS;
Ld_=10.^((fPL(dd_v_,n_NLOS,b_NLOS)-Xd_)/10);
bd_f_=(randn(Md_,Nsym)+1i*randn(Md_,Nsym))/sqrt(2);
D_NLOS=(sum(bd_f_.*sqrt(Ld_),1)/sqrt(Md_)).';
D=D_LOS+D_NLOS;
end

% -------------------------------------------------------------------------
function [h,g,d]=SimRIS_v18_det(Environment,Scenario,Frequency,ArrayType,N,Nt,Nr,Tx_xyz,Rx_xyz,RIS_xyz)
% Canal deterministico: perda de percurso media sem shadow fading e sem fast fading.
% LOS ponderada por sqrt(p_LOS); NLOS pelo ganho medio de potencia isotropico.
% Formula final: |C|^2 = (N * amp_h * amp_g + amp_d)^2 — unica avaliacao, sem variancia.
% Retorna h (N×1), g (N×1), d (escalar real positivo).

lambda=3e8/(Frequency*1e9); kw=2*pi/lambda; dis_=lambda/2;
x_Tx=Tx_xyz(1);y_Tx=Tx_xyz(2);z_Tx=Tx_xyz(3);
x_Rx=Rx_xyz(1);y_Rx=Rx_xyz(2);z_Rx=Rx_xyz(3);
x_RIS=RIS_xyz(1);y_RIS=RIS_xyz(2);z_RIS=RIS_xyz(3);
sN_=sqrt(N); xv_=floor((0:N-1)/sN_); yv_=mod(0:N-1,sN_);
if Environment==1, n_NLOS=3.19;b_NLOS=0.06;f0=24.2;n_LOS=1.73;b_LOS=0;
else,              n_NLOS=3.19;b_NLOS=0;   f0=24.2;n_LOS=1.98;b_LOS=0; end
q_=0.285; Gn=pi;
PL0=-20*log10(4*pi/lambda);
fPL=@(dist,n,b) PL0-10*n*(1+b*((Frequency-f0)/f0))*log10(max(dist,1e-3));
safe_atand=@(y,x) atand(y/max(abs(x),1e-6))*sign(x);
safe_asind=@(r,d) asind(min(abs(r)/max(d,1e-6),1))*sign(r);

% ---- p_LOS helpers ----
if Environment==1
    plos_in=@(d,zr,zt) (zr>=zt)*1 + (zr<zt)*(d<=1.2 + (d>1.2)*(d<6.5)*exp(-(d-1.2)/4.7) + (d>=6.5)*0.32*exp(-(d-6.5)/32.6));
    pL_h = plos_in(norm(Tx_xyz-RIS_xyz), z_RIS, z_Tx);
    pL_g = 1;  % indoor g sempre LOS no modelo original
    pL_d = plos_in(norm(Tx_xyz-Rx_xyz), z_RIS, z_Tx);
else
    plos_out=@(d) min(20/d,1)*(1-exp(-d/39))+exp(-d/39);
    pL_h = plos_out(norm(Tx_xyz-RIS_xyz));
    pL_g = plos_out(norm(RIS_xyz-Rx_xyz));
    pL_d = plos_out(norm(Tx_xyz-Rx_xyz));
end

% ---- h: Tx -> RIS ----
d_TR=norm(Tx_xyz-RIS_xyz);
L_LOS_h=10^(fPL(d_TR,n_LOS,b_LOS)/10);
L_NLOS_h=10^(fPL(d_TR,n_NLOS,b_NLOS)/10);
if Scenario==1
    ph_h=safe_atand(x_RIS-x_Tx, y_RIS-y_Tx); th_h=safe_asind(z_RIS-z_Tx, d_TR);
else
    ph_h=safe_atand(y_RIS-y_Tx, x_RIS-x_Tx); th_h=safe_asind(z_RIS-z_Tx, d_TR);
end
aH_=exp(1i*kw*dis_*(xv_*sind(th_h)+yv_*sind(ph_h)*cosd(th_h))).';  % N×1
amp_h=sqrt(pL_h*L_LOS_h*Gn*(cosd(th_h))^(2*q_) + (1-pL_h)*L_NLOS_h);
h=amp_h*aH_;  % LOS steering, amplitude = mean total power (LOS + NLOS isotropico)

% ---- g: RIS -> Rx ----
d_RR=norm(RIS_xyz-Rx_xyz);
L_LOS_g=10^(fPL(d_RR,n_LOS,b_LOS)/10);
L_NLOS_g=10^(fPL(d_RR,n_NLOS,b_NLOS)/10);
if Environment==1 || Scenario==1
    ph_g=safe_atand(x_RIS-x_Rx, y_RIS-y_Rx); th_g=safe_asind(z_RIS-z_Rx, d_RR);
else
    ph_g=safe_atand(y_RIS-y_Rx, x_RIS-x_Rx); th_g=safe_asind(z_RIS-z_Rx, d_RR);
end
aG_=exp(1i*kw*dis_*(xv_*sind(th_g)+yv_*sind(ph_g)*cosd(th_g))).';
amp_g=sqrt(pL_g*L_LOS_g*Gn*(cosd(th_g))^(2*q_) + (1-pL_g)*L_NLOS_g);
g=amp_g*aG_;

% ---- d: Tx -> Rx direto ----
d_TRx=norm(Tx_xyz-Rx_xyz);
L_LOS_d=10^(fPL(d_TRx,n_LOS,b_LOS)/10);
L_NLOS_d=10^(fPL(d_TRx,n_NLOS,b_NLOS)/10);
d=sqrt(pL_d*L_LOS_d + (1-pL_d)*L_NLOS_d);  % real escalar: raiz da potencia media
end

% -------------------------------------------------------------------------
function k = poissrnd_local(lambda)
% Amostra Poisson(lambda) sem o Statistics Toolbox (algoritmo de Knuth).
% Usado no lugar de poissrnd no ramo outdoor (Env==2) do SimRIS.
    L = exp(-lambda);
    k = 0;
    p = 1;
    while true
        k = k + 1;
        p = p * rand;
        if p <= L
            break;
        end
    end
    k = k - 1;
end