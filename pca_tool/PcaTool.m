classdef PcaTool < GuiBase & MObject
  %PCATOOL Pca tool GUI
  %   Detailed explanation goes here
  
properties (GetAccess = public, SetAccess = private)
  mainH % GUI figure
  scores % scores ScatterSelect
  loadings % loadings ScatterSelect  
  pm % Presentation model  
  settingsFile % mat-file where settings are stored
  lastSaveGenes % last save filename for genes
  lastSaveSamples % lastfilename for  samples
end


methods
  function self = PcaTool(computeObj)
  % computeObj is an object derived from PcaComputeBase
    self@MObject();
    self@GuiBase();    
    % wire presentation model signals 
    p = PcaToolPM(computeObj);
    p.connectMe('reset_changed', @self.refresh);
    p.connectMe('highlight_changed', @self.updateAnnotationInfo);
    p.connectMe('selection_changed', @self.updateLists);
    self.pm = p;
    self.settingsFile = fullfile(pwd, 'settings.mat');
    self.lastSaveGenes = '';
    self.lastSaveSamples = '';
  end

  function show(self)
    if ishandle(self.mainH)
      set(self.mainH, 'Visible', 'on');
      self.registerCallbacks();
    else
      self.registerCallbacks();
      fig = pca_tool2('HandleVisiblity', 'off');
      self.mapUiControls(fig);
      set(fig, 'CloserequestFcn', @self.windowAboutToClose);
      % save callbacks
      handles = guidata(fig);
      handles.n = {self};
      guidata(fig, handles);
      self.mainH = fig;
      self.createScatterPlots();
      self.loadSettings();
      self.refresh();
      self.updateAvailableFeatures();
      self.loadings.show();
      self.scores.show();
    end
  end

  function refresh(self)
    set(self.pcaxEditH, 'String', num2str(self.pm.pcaxInd));
    set(self.pcayEditH, 'String', num2str(self.pm.pcayInd));
    switch self.pm.clusterMethod
      case ClusteringMethod.KMeans
        ind = 1;
      case ClusteringMethod.Gaussian
        ind = 2;
      case ClusteringMethod.Minkowski
        ind = 3;
      case ClusteringMethod.User
        ind = 4;      
      otherwise
        error('Bug found');
    end    
    set(self.clusteringPopupH, 'Value', ind);
    self.refreshPcaButtonH_Callback();
    self.updateAnnotationInfo();
    self.updateLists();
  end
  
  %*** Callbacks from GUI objects defined in GUIDE
  function refreshPcaButtonH_Callback(self, varargin)
    self.pm.updateCurrentPca();
    self.scores.updateData(self.pm.scoreXY, self.pm.cluster);
    self.loadings.updateData(self.pm.coefXY, self.pm.cluster);
  end

  function pcaxEditH_Callback(self, varargin)
    ind = str2double(get(self.pcaxEditH, 'String'));
    self.pm.pcaxInd = ind;
  end
  
  function pcayEditH_Callback(self, varargin)
    ind = str2double(get(self.pcayEditH, 'String'));
    self.pm.pcayInd = ind;
  end
  
  function clusteringPopupH_Callback(self, varargin)
    ind = get(self.clusteringPopupH, 'Value');
    switch ind
      case 1
        self.pm.clusterMethod = ClusteringMethod.KMeans;
      case 2
        self.pm.clusterMethod = ClusteringMethod.Gaussian;
      case 3
        self.pm.clusterMethod = ClusteringMethod.Minkowski;
      case 4
        self.pm.clusterMethod = ClusteringMethod.User;        
      otherwise
        error('Bug found');
    end
  end
  
  function clusterCellsButtonH_Callback(self, varargin)
    self.pm.updateCurrentClustering();
    self.refreshPcaButtonH_Callback();
  end
  
  function sampleListboxH_Callback(self, varargin)
    self.pm.sampleListInd = get(self.sampleListboxH, 'Value');
  end
  
  function geneListboxH_Callback(self, varargin)
    self.pm.geneListInd = get(self.geneListboxH, 'Value');
  end
  
  function clearGeneListButtonH_Callback(self, varargin)
    self.pm.selectionChanged('gene', [], []);
  end
  
  function clearSampleListButtonH_Callback(self, varargin)
    self.pm.selectionChanged('sample', [], []);
  end
  
  function saveSampleListButtonH_Callback(self, varargin)
    savedAs = self.openDialogAndSaveAsText('Save samples', ...
      self.lastSaveSamples, get(self.sampleListboxH, 'String'));
    if ~isempty(savedAs)
      self.lastSaveSamples = savedAs;
    end
  end
  
  function saveGeneListButtonH_Callback(self, varargin)
    savedAs = self.openDialogAndSaveAsText('Save genes', ...
      self.lastSaveGenes, get(self.geneListboxH, 'String'));
    if ~isempty(savedAs)
      self.lastSaveGenes = savedAs;
    end    
  end
  
  %*** 
  function saveSettingsAndQuit(self)
    self.saveSettings();
    % Delete all figs
    self.loadings.closeFigure();
    self.scores.closeFigure();
    delete(self.mainH);
  end
  
end

%*** Private implementation related stuff
methods (Access = private)
  function updateAvailableFeatures(self)
%     tags ={'saveGeneListButtonH', 'addTopGenesButtonH', ...
%       'deleteGeneButtonH', 'ontologyButtonH',...
%       'cutoffEditH', 'pc1PopupH', 'posPopupH', 'findGeneButtonH', ...
%       'geneSymbolEditH', 'deleteSampleButtonH', ...
%       'refreshPcaUsingSamplesButtonH', 'findSampleButtonH', ...
%       'sampleSymbolEditH', 'saveSampleListButtonH', 'tracePopupH', ...
%       'runTraceButtonH'};
    tags ={ 'tracePopupH', 'runTraceButtonH', 'ontologyButtonH'};
    for i = 1:length(tags)
      set(self.(tags{i}), 'Enable', 'off');
    end
  end
  
  function savedAs = openDialogAndSaveAsText(self, title, lastSave, data)
  % data is a cell array of strings
    [fname, pname, ~] = uiputfile(lastSave, title);
    if fname ~= 0
      savedAs = fullfile(pname, fname);
      fid = fopen(savedAs, 'w', 'n', 'UTF-8');
      for i=1:length(data)
        fprintf(fid, '%s\n', data{i});
      end
      fclose(fid);
    else
      savedAs = [];
    end
  end
  
  function windowAboutToClose(self, varargin)
    self.saveSettingsAndQuit();
  end
  
  function createScatterPlots(self)
  % Creates scatter plot windows, signals are fed to the presentation
  % model which handles the UI logic
    % pca scores
    s = ScatterSelect();
    s.title = 'PCA scores';
    s.selectingEnabled = true;
    s.highMarker = '*';
    s.closeFcn = @self.saveSettingsAndQuit;
    s.connectMe('is_in', @(x)registerIsIn(self.pm, 'sample', x));
    s.connectMe('highlight', @(x)highlightChanged(self.pm, 'sample', x));
    s.connectMe('selection', ...
       @(x,y)self.pm.selectionChanged('sample', x,y));
    self.scores = s;
    % pca loadings
    s = ScatterSelect();
    s.title = 'PCA loadings';
    s.selectingEnabled = true;
    s.highMarker = '*';
    s.closeFcn = @self.saveSettingsAndQuit;
    s.connectMe('is_in', @(x)registerIsIn(self.pm, 'gene', x));
    s.connectMe('highlight', @(x)highlightChanged(self.pm, 'gene', x));
    s.connectMe('selection', ...
       @(x,y)selectionChanged(self.pm, 'gene', x,y));    
    self.loadings = s;
  end
  
  function updateButtons(self)
    tags = {'deleteGeneButtonH', 'clearGeneListButtonH', ...
      'saveGeneListButtonH', 'deleteSampleButtonH', ...
      'clearSampleListButtonH', 'saveSampleListButtonH',...
      'refreshPcaUsingSamplesButtonH'};
    props = {'deleteGeneEnable', 'clearGeneListEnable', ...
      'saveGeneListEnable', 'deleteSampleEnable', ...
      'clearSampleListEnable', 'saveSampleListEnable', ...
      'refreshPcaUsingSamplesEnable'};
    state = self.pm.uiState;
    for i = 1:length(tags)
      tag = tags{i};
      prop = props{i};
      if state.(prop)
        onOff = 'on';
      else
        onOff = 'off';
      end
      set(self.(tag), 'Enable', onOff);
    end
  end

  function updateAnnotationInfo(self)
    self.updateGeneAnnotations(self.pm.geneHighInd);
    self.updateCellAnnotations(self.pm.sampleHighInd);
  end
  
  function updateGeneAnnotations(self, ind)
    if ~isempty(ind)
       symbolText = self.pm.getAnnotation('symbol_text', ind);
       medianText = num2str(self.pm.getAnnotation(...
         'median_number', ind));
      dispersionText = num2str(self.pm.getAnnotation(...
        'dispersion_number', ind));
      expressingText = num2str(self.pm.getAnnotation(...
        'expressing_number', ind));      
    else
      symbolText = '-';
      medianText = '-';
      dispersionText = '-';
      expressingText = '-';
    end
    set(self.symbolTextH, 'String', symbolText);
    set(self.medianTextH, 'String', medianText);
    set(self.dispersionTextH, 'String', dispersionText);
    set(self.expressingTextH, 'String', expressingText);    
  end
  
  function updateCellAnnotations(self, ind)
    titleText = 'Cell annotations';
    if ~isempty(ind)
      titleText = [titleText ' (ID ' ...
        self.pm.getAnnotation('id_text', ind) ')'];
      tagsText = num2str(self.pm.getAnnotation('tags_number', ind));
      genesText = num2str(self.pm.getAnnotation('genes_number', ind)); 
      preseqText = num2str(self.pm.getAnnotation('preseq_number', ind)); 
      simpsonText = num2str(self.pm.getAnnotation('simpson_number', ind)); 
      binomialText = num2str(self.pm.getAnnotation(...
                                              'binomial_number', ind)); 
    else
      tagsText = '-';
      genesText = '-';
      preseqText = '-';
      simpsonText = '-';
      binomialText = '-';
    end
    set(self.cellPanelH, 'Title', titleText);
    set(self.tagsTextH, 'String', tagsText);
    set(self.genesTextH, 'String', genesText);
    set(self.preseqTextH, 'String', preseqText);
    set(self.simpsonTextH, 'String', simpsonText);
    set(self.binomialTextH, 'String', binomialText);
  end
  
  function updateLists(self)
    self.updateGeneList();
    self.updateSampleList();
  end
  
  function updateGeneList(self)    
    ind = self.pm.geneSelIndices;
    N = length(ind);
    list = cell(N, 1);
    for i = 1:N
      list{i} = self.pm.getAnnotation('symbol_text', ind(i));
    end
    ind = self.pm.geneListInd;
    if isempty(ind)
      set(self.geneListboxH, 'String', 'Add genes to the list', ...
        'Value', 1);
    else
      set(self.geneListboxH, 'String', list, 'Value', ind);
    end
    self.updateButtons();
  end
  
  function updateSampleList(self)
    ind = self.pm.sampleSelIndices;
    N = length(ind);
    list = cell(N, 1);
    for i = 1:N
      list{i} = self.pm.getAnnotation('id_text', ind(i));
    end
    ind = self.pm.sampleListInd;
    if isempty(ind)
      set(self.sampleListboxH, 'String', 'Add samples to the list', ...
        'Value', 1);
    else
      set(self.sampleListboxH, 'String', list, 'Value', ind);
    end
  end
  
  function saveSettings(self)
  % Save settings, e.g, figure locations, etc., when closing the tool    
    settings = struct;      
    settings.main = get(self.mainH, 'Position');
    settings.loadings = self.loadings.getSettings();
    settings.scores = self.scores.getSettings();
    settings.pm = self.pm.getSettings();
    settings.lastSaveGenes = self.lastSaveGenes;
    settings.lastSaveSamples = self.lastSaveSamples;
    save(self.settingsFile, 'settings');
  end

  function loadSettings(self)
  % Load settings when the tool is opened
  % For some reason, setting the GUI window position does not work
    if exist(self.settingsFile, 'file')
      tmp = load(self.settingsFile);
      settings = tmp.settings;
      set(self.mainH, 'Position', settings.main);
      self.loadings.changeToSettings(settings.loadings);
      self.scores.changeToSettings(settings.scores);
      self.pm.changeToSettings(settings.pm);
      self.lastSaveGenes = settings.lastSaveGenes;
      self.lastSaveSamples = settings.lastSaveSamples;      
    end
  end  
end
end

