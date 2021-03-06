 function results = fastpolarize(dim,maxt,varargin)
% polarize(dim,maxt) -- Simulate polarization in a scientific community.
% based on:  O'Connor, Cailin & Weatherall, James Owen (2017). Scientific 
% polarization. _European Journal for Philosophy of Science_ 8 (3):855-875.
%
% MANDATORY INPUTS:
% dim: dimensions of square map
% maxt: maximum number of timesteps to run (user can abort early)
%
% OPTIONAL INPUTS:
% degree: the size of each scientist's neighborhood. A measure of community
% connectedness.
% p: P_B, the success rate of the better option B 
% (between .501 and .8). Remember P_A is the success rate of the alternate 
% option A (always .5). 
% n: the number of tests each scientists runs in every round of their 
% experiments, from 1 to 100.
% m: the multiplier that determines how quickly scientists begin to mistrust
% those with different beliefs, looking at values from 1 to 3.
% initialMap: the map at time t=0
% display: whether or not the visual representation of the simulation
% should be displayed
% output: what type of result to return. Can be the final proportion of the
% population that reached the correct conclusion ('correct'), the entropy 
% through time ('entropy'), or the final map of the community ('map').
%
% OUTPUTS: 
% proportionCorrect: the final proportion of scientists who believe in the 
% correct hypothesis (that action B is more successful than action A) 
% timeToConsensus: how many time steps it took for the viewpoints of the
% scientific community to stabilize to their final result
% mapEntropy: the entropy of the final result, a statistical measure of 
% how nonhomogeneous the community is.
% 
% IMPLEMENTATION:
% We start with a dim x dim community of scientists, where each agent in 
% the network has some credence between 0 and 1 that action B is better 
% than action A. The success rate of action A is known to be .5, while that 
% of action B is unknown to the scientists. At each timestep, each scientist
% who believes action B is better than action A performs an experiment
% where they try action B n times and count the successes (a Bernoulli 
% trial). 
% The scientists also each have an unchanging neighborhood of size degree
% comprised of the scientists nearest them. Each scientist then
% updates their credence that B is better than A based on the new evidence
% of any scientists in their neighborhood. This update is modeled using the
% equation given in Scientific Polarization by Cailin O?Connor and James 
% Owen Weatherall, and uses a combination of Bayes' rule, Jeffrey
% conditionalization, and the premise that scientists may disbelieve in the
% experimental results of scientists they perceive to be untrustworthy 
% sources. 
% Once the scientific communities' credences are stable, or maxt time steps
% have occurred, the simulation terminates. The community may end in a
% state of correct consensus (all scientists believe B>A), incorrect
% consensus (all scientists believe A>B), or polarization, 
%   
% SAMPLE CALL:
% polarize(dim,10,d,p,n,m,'display',false);
% 
% BY Zoe Koch, 2/15/19

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% READ IN THE INPUT VARIABLES
inputs = inputParser;

defaultDegree = min(dim^2,9);
validDegree = @(x) isnumeric(x) && isscalar(x) && (x >= 1)&& (x <= dim^2);
defaultP = .7;
validProb = @(x) isnumeric(x) && isscalar(x) && (x >= .501)&& (x <=.8);
defaultN = 10;
validN = @(x) isnumeric(x) && isscalar(x) && (x >= 1)&& (x <=100);
defaultM = 1.5;
validM = @(x) isnumeric(x) && isscalar(x) && (x >= 1)&& (x <=3);
defaultInitialMap = rand(dim,dim);
validMap = @(x) isequal(size(x),[dim,dim]);
defaultOutput = 'correct';

addOptional(inputs,'degree',defaultDegree,validDegree);
addOptional(inputs,'p',defaultP,validProb);
addOptional(inputs,'n',defaultN,validN);
addOptional(inputs,'m',defaultM,validM);
addOptional(inputs,'initialMap',defaultInitialMap,validMap);
addOptional(inputs,'mapGranularity',20);
addOptional(inputs,'display',true);
addOptional(inputs,'output',defaultOutput);
addOptional(inputs,'pValues',nan);
addOptional(inputs,'updateValues',nan);

parse(inputs,varargin{:});
map = inputs.Results.initialMap;
degree = inputs.Results.degree;
p = inputs.Results.p;
n = inputs.Results.n;
m = inputs.Results.m;
display = inputs.Results.display;
output = inputs.Results.output;
% pValues = inputs.Results.pValues;
% updateValues = inputs.Results.updateValues;
mapGranularity = inputs.Results.mapGranularity;
entropyResults = zeros(1,maxt);

% Improve speed by making it so you don't have to re-calculate these
% persistent variables each time you call the function.
persistent P_E P_iEH P_inotEH updateValues 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% PLOT INITIAL MAP (see function below)
if display
    [fighandle,plothandle] = plotMapInNewFigure(map); 
end

% CALCULATE VALUES THAT ARE CONSTANT THROUGH EACH TIMESTEP.

% Create the neighborhood of each scientist.
NBD = zeros(dim^2,degree);
for i=1:dim^2
    NBD(i,:) = createNbd(i, dim, degree);
end

% Calculate the initial probabilities for each possible evidence value E.
if isempty(P_E)
    P_E = arrayfun(@(E) P_Efun(E,n), 0:n);
    P_iEH = arrayfun(@(E) P_EGivenH(E,n,true), 0:n);
    P_inotEH = arrayfun(@(E) P_EGivenH(E,n,false), 0:n);
end

% Calculate how much a given scientist will update their beliefs given 
% a neighbor's evidence. Store results in the matrix updateValues.
if isempty(updateValues)
    updateValues = zeros(1+mapGranularity,1+mapGranularity,1+n);
    for myCredence=0:mapGranularity
        for neighborCredence=0:mapGranularity
            for e = 0:n
                updateValues(1+myCredence,1+neighborCredence,1+e) = checkEvidence(m,n,e,...
                    myCredence/mapGranularity,neighborCredence/mapGranularity,...
                    P_E(e+1),P_iEH(e+1),P_inotEH(e+1)); 
            end
        end
    end  
end

% TRANSITION THE MAP THROUGH EACH TIMESTEP 
for t=1:maxt 

%     The scientists who believe action B is better than action A run
%     their experiment, performing action B n times and counting successes,
%     which is their new evidence. 
    evidence = zeros(size(map));
    evidence(:) = nan;
    evidence(map>=.5) = binornd(n,p,[1,nnz(map>=.5)]); 
    
%     Each scientist looks at all the new evidence and updates their
%     credence accordingly. Their new credence will be the update
%     values (stored in P_f), averaged over all of their neighbors. 
    oldMap = map;   
    for i=1:numel(map) % Loop over each scientist.
        nbrInd = NBD(i,:);
        % Ignore neighbors who don't have new evidence
        nbrInd = nbrInd(not(isnan(evidence(nbrInd)))); 
%       If no one in the neighborhood ran an experiment, there will be no
%       update.
        if isempty(nbrInd)
            continue;
        end
        
        P_f = arrayfun(@(j) getUpdateValue(i,j,oldMap,evidence,...
            mapGranularity,updateValues), nbrInd);
        map(i) = mean(P_f);
    end 

    % UPDATE PLOT WITH NEW MAP DATA
    if display
        set(plothandle,'cdata',map); 
%         set(gcf, 'Units', 'Normalized', 'OuterPosition', [0 0 1 1]);  
        figure(gcf),drawnow; % Force matlab to show the figure

       % Bail out if the user closed the figure
        if ~ishandle(fighandle)
            plotMapInNewFigure(map); % Plot final map and exit
            title('Final configuration')
            break
        end
    end
    
%       RECORD RESULTS
% Track entropy
    entropyResults(t) = entropy(map);
    
% End the simulation and record results once the credences are stable. A
% stable outcome is one in which every agent either (a) has credence > .99
% or else (b) has credence <= .5 such that their distance to all agents 
% whose credence is > .99 satisfies m * d >= 1.) m from 0 to 3
    if (nnz(map>.99) + nnz(map<=min(.5, max(.01,1-1/m))) == dim^2 || nnz(map>=.5)==0)
        continue;
%     elseif t==maxt
%         warning('The simulation did not complete in fewer than the maximum time steps.')
    end
end 

switch output
    case 'correct'
        results = nnz(map>.5)/numel(map);
    case 'map'
        results = map;
    case 'entropy'
        results = entropyResults;
    case 'polarized'
        results = sum(map(:)<.5)==dim^2 || sum(map(:)>.99)==dim^2;
    case 'storedValues'
        results = {P_E, P_iEH, P_inotEH, updateValues};
    otherwise
        error("Invalid output argument. Must be 'correct', 'map', 'entropy', or 'storedValues'.") 
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [fighandle,plothandle] = plotMapInNewFigure(map)
% Helper function to plot the map
fighandle=figure;
set(fighandle,'position',[42   256   560   420]); % specify location of figure
plothandle=imagesc(map); % doesn't truncate a row and col like pcolor does
colormap(jet);
set(gca,'clim',[0 1]); % make sure the color limits down change dynamically
set(gca,'XTickLabel',[]);
set(gca,'YTickLabel',[]);
ch=colorbar;
set(ch,'Ytick',[0 1],'Yticklabel',{'Incorrect','Correct'})
axis('square') %make sure aspect ratio is equal

function nbd = createNbd(i, dim, degree)
% Creates the indexes of the neighborhood of the scientist at index i.
% Each scientist's neighborhood is the block of scientists immediately 
% surrounding them, and possibly a few scientists randomly chosen from 
% nearest that block (if the degree is not a perfect square). 
% The scientist of interest is included in their own neighborhood.
% The map is terroidal.

% Collect the indexes of all the neighbors in a square block around the
% scientist of interest.
margin = max(0,floor(ceil(sqrt(degree))/2-1));
smallBlock = createBlock(i,margin,dim);
nbd = smallBlock;

% If you still need more neighbors, randomly select some from the square
% surrounding the smaller block.
excess = degree - numel(smallBlock); 
if excess
    largeBlock = createBlock(i,margin+1,dim);
    outerSquare = setdiff(largeBlock, smallBlock);
    outerNbd = outerSquare(randperm(numel(outerSquare),excess));
    nbd = cat(1, smallBlock, outerNbd);
end


function index = terroidal(i,j,dim)
% Translate from row and column subscripts to linear indexing, keeping in 
% mind the array is terroidal.

i = mod(i,dim);
j = mod(j,dim);

if i == 0
    i = dim;
end
if j == 0
    j = dim;
end

index = sub2ind([dim,dim],i,j);

function block = createBlock(i,margin,dim)
% Return indexes of the a block around a position i in a dim x dim array.
[myi,myj] = ind2sub([dim,dim],i);

I = myi-margin:myi+margin;
J = myj-margin:myj+margin;

blockWidth = margin*2 + 1;
block = zeros(blockWidth^2,1);
for i=1:blockWidth
    for j=1:blockWidth
        block(i+(j-1)*blockWidth) = terroidal(I(i),J(j),dim);
    end
end

function P_fH = checkEvidence(m,n,E,myCredence,neighborCredence,P_E,P_iEH,P_inotEH)       
% checkEvidence(myIndex, neighborIndex, oldMap, evidence, n, m) --
% Calculates the update a scientist Jill should have upon seeing evidence E
% produced by another scientist Ian. 
% d: the distance between Ian's and Jill's beliefs
% P_iE = Jill's initial probability of the evidence occurring given her 
% beliefs about theory A and theory B
% P_fE: Jill's credence that Ian's evidence is real, from the original
% paper
% P_fnotE: Jill's belief that Ian's evidence is NOT real
% P_iEH: the probability of Ian's evidence, given theory B is better than
% theory A
% P_iHE: the belief Jill would obtain via strict conditionalization on 
% Ian's evidence, from Bayes' rule
% P_iHnotE: the belief Jill would obtain via strict conditionalization had
% Ian's evidence not occurred
% P_fH: Jill?s final belief in the hypothesis that theory B is better than
% theory A, from  Jeffrey conditionalization
% MANDATORY INPUTS:
% m: a multiplier that captures how quickly agents become uncertain
% about the evidence of their peers as their beliefs diverge. 
% n: The number of rounds in the scientists' experiments.
% E: the evidence of Ian. The results of his experiment.
% myCredence: Jill's initial belief P_B is better than P_A
% neighborCredence: Jill's initial belief P_B is better than P_A
% P_E: the probability of Ian's evidence occurring. The marginal likelihood 
% or "model evidence". 
% P_iEH: the probability of Ian's evidence, given theory B is better than
% theory A
% P_inotEH: the probability of NOT Ian's evidence, given theory B is better 
% than theory A

d = abs(myCredence-neighborCredence); 
P_iE = binopdf(E,n,myCredence);
P_fE = max(1 - d*m*(1-P_iE), 0); % From the paper Scientific Polarization

% P_iHE = P_iEH * myCredence/ P_E; % Bayes' rule
P_iHE = P_iEH * .9/ P_E; % Bayes' rule

% P_iHE = P_iEH * myCredence/ P_iE; % Bayes' rule

P_fnotE = 1-P_fE;
P_notE = 1 - P_E;
P_iHnotE = P_inotEH * myCredence/ P_notE; % Bayes' rule
% P_iHnotE = P_inotEH * 1/ P_notE; % Bayes' rule


P_fH = P_iHE * P_fE + P_iHnotE * P_fnotE; % Jeffrey conditionalization

function P_E = P_Efun(E,n)
% Calculate the probability of evidence E occurring.  
% The marginal likelihood or "model evidence". 
pdf = @(p) binopdf(E,n,p);
P_E = integral(pdf,0,1);

function P_iEH = P_EGivenH(E,n,eHappened)
% Calculate the probability of evidence E (or ~E if eHappened is false) 
% given the hypothesis H that action B is better than action A.
if eHappened
    pdf = @(p) binopdf(E,n,p);
else
    pdf = @(p) 1-binopdf(E,n,p);
end
P_iEH = integral(pdf,.5,1);

function updateValue = getUpdateValue(i,j,map,evidence,mapGranularity, updateValues)
% Retrieves the updateValue by translating the map values and indexes into
% the correct indices for the updateValues matrix.
% INPUTS:
% i: the index of the current scientist
% j: the index of the current scientists' neighbor
% map: the credences matrix
% evidence: the evidence matrix
% mapGranularity: the measure of, determines how much we're rounding our
% map values in the updateValues matrix.
% updateValues: the updateValues matrix.
m_ind = 1+min(round(map(i)*mapGranularity),mapGranularity);
n_ind = 1+min(round(map(j)*mapGranularity),mapGranularity);
e_ind = 1+evidence(j);
updateValue = updateValues(m_ind,n_ind,e_ind);
