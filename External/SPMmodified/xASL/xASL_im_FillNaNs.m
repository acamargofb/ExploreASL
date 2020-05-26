function [IM] = xASL_im_FillNaNs(InputPath, UseMethod, bQuality, VoxelSize, x)
%xASL_im_FillNaNs Fill NaNs in image
% FORMAT: xASL_im_FillNaNs(InputPath[, UseMethod, bQuality])
%
% INPUT:
%   InputPath   - path to image, or image matrix (REQUIRED)
%                 NB: if this is a path, it is overwritten
%   UseMethod   - one of the following methods to fill the NaNs:
%                 1: extrapolate by smoothing (useful for any image, e.g.
%                    extrapolating M0 smooth biasfield) (DEFAULT)
%                 2: set to 0 (useful for e.g. DARTEL displacement fields,
%                    where 0 means no displacement)
%                 3: linearly extrapolate flow field (e.g. for transformation
%                    mapping)
%                 (OPTIONAL, DEFAULT = 1)
%   bQuality    - affects kernel size of the extrapolation performed in method 1
%                 (extrapolating by smoothing goes much faster with smaller
%                 kernel but this creates ringing artifacts)
%                 (OPTIONAL, DEFAULT = 1)
%   VoxelSize   - [X Y Z] vector for voxel size 
%                 (OPTIONAL, DEFAULT = [1.5 1.5 1.5])
%   x           - ExploreASL parameter struct (REQUIRED for option 3)
%
% OUTPUT:
%   IM          - image matrix in which NaNs were filled
% --------------------------------------------------------------------------------------------------------------------
% DESCRIPTION: This function fills any NaNs in an image. In SPM, any voxels
%              outside the boundary box/field of view are filled by NaNs
%              when resampling. These NaNs can confuse some algorithms,
%              hence it doesn't hurt replacing them in some cases (e.g. for
%              flowfields). Also, smoothing restricted in a mask is done in
%              ExploreASL with the function xASL_im_ndnanfilter, after
%              first setting all voxels outside the mask to NaN. In this
%              case, this functon can be useful to extrapolate the smoothed
%              image to avoid any division artifact near brain edges (e.g.
%              for reducing the M0 image to a smooth biasfield).
%              This function performs the following 3 steps:
%              1) Load image
%              2) Replace NaNs
%              3) Save image
% --------------------------------------------------------------------------------------------------------------------
% EXAMPLE for filling NaNs: xASL_im_FillNaNs('/MyStudy/sub-001/ASL_1/M0.nii');
% EXAMPLE for fixing flowfield edges: xASL_im_FillNaNs('/MyStudy/sub-001/y_T1.nii', 3);
% __________________________________
% Copyright (C) 2015-2019 ExploreASL

%% Admin
IM = NaN; % default

if nargin<1 || isempty(InputPath)
    warning('Illegal input path, skipping');
    return;
end

if nargin<2 || isempty(UseMethod)
    UseMethod = 3;
elseif UseMethod<0 || UseMethod>3
    warning('Illegal option chosen, setting to default value');
    UseMethod = 3;
end

if nargin<3 || isempty(bQuality)
    bQuality = 1; % default
elseif bQuality~=0 && bQuality~=1
    warning('Illegal bQuality setting!!!');
    bQuality = 1; % default
end

if UseMethod==1 % only method that needs VoxelSize
    if nargin<4 || isempty(VoxelSize)
        if ~isnumeric(InputPath) && xASL_exist(InputPath, 'file')
            nii = xASL_io_ReadNifti(InputPath);
            VoxelSize = nii.hdr.pixdim(2:4);
        elseif bQuality
                warning('Voxel size not specified, using default [1.5 1.5 1.5]');
                % only when high quality will we use this parameter,
                % so we dont give this warning for low quality
                VoxelSize = [1.5 1.5 1.5];
        else
                VoxelSize = [1.5 1.5 1.5];
        end
        
    end
end

if nargin<5 || isempty(x)
    x = struct;
end

%% ------------------------------------------------------------------------------
%% 1) Load image
IM = xASL_io_Nifti2Im(InputPath); % allows loading image from path or from image


%% ------------------------------------------------------------------------------
%% 2) Replace NaNs
fprintf('%s', 'Cleaning up NaNs in image:  0%');
TotalDim = size(IM,4)*size(IM,5)*size(IM,6)*size(IM,7);
CurrentIt = 1;

for i4=1:size(IM,4)
    for i5=1:size(IM,5)
        for i6=1:size(IM,6)
            for i7=1:size(IM,7)
                xASL_TrackProgress(CurrentIt, TotalDim);

                switch UseMethod
                    case 1
                        IM(:,:,:,i4,i5,i6,i7) = xASL_im_ExtrapolateSmoothOverNaNs(IM(:,:,:,i4,i5,i6,i7), bQuality, VoxelSize);
                    case 2
                        IM(isnan(IM)) = 0;
                        % This loops unnecessary but goes fast
                        % enough, keep in this loop for readability
                    case 3
                        IM(:,:,:,i4,i5,i6,i7) = xASL_im_ExtrapolateLinearlyOverNaNs(IM(:,:,:,i4,i5,i6,i7));
                    otherwise
                        error('Invalid option');
                end

                CurrentIt = CurrentIt+1;
            end
        end
    end
end

fprintf('\n');
        

%% ------------------------------------------------------------------------------
%% 3) Save image
% Here we only output an image if the input path was a path and not an
% image matrix
if ~isnumeric(InputPath) && xASL_exist(InputPath, 'file')
    xASL_io_SaveNifti(InputPath, InputPath, IM, [], 0);
end


end


%% ========================================================================================
%% ========================================================================================
function [IM] = xASL_im_ExtrapolateSmoothOverNaNs(IM, bQuality, VoxelSize)
%xASL_im_ExtrapolateLinearlyOverNaNs

    if sum(isnan(IM(:))) < numel(IM)
        while sum(sum(sum(isnan(IM))))>0 % loop extrapolation until full FoV is filled
            if bQuality==1
                IM = xASL_im_ndnanfilter(IM,'gauss', double([12 12 12]./VoxelSize), 2); % 2 at the end means extrapolation only
            else
                IM = xASL_im_ndnanfilter(IM,'gauss', double([2 2 2]), 2); % smaller kernel goes much faster
            end
        end
    else
        % Image contains only NaNs - skip this image
    end


end


%% ========================================================================================
%% ========================================================================================
function [IM] = xASL_im_ExtrapolateLinearlyOverNaNs(IM)
%xASL_im_ExtrapolateLinearlyOverNaNs

    %% THIS CONTAINS TEMPORARILY A COPY OF OPTION 1 BUT WITH SMALLER KERNEL, 
    %% FOR JAN PETR TO REPLACE TO THE CORRECT EXTRAPOLATE LINEARLY OVER NANS
    
    if sum(isnan(IM(:))) < numel(IM)
        while sum(sum(sum(isnan(IM))))>0 % loop extrapolation until full FoV is filled
            IM = xASL_im_ndnanfilter(IM,'gauss', double([2 2 2]), 2); % smaller kernel goes much faster
        end
    else
        % Image contains only NaNs - skip this image
    end


end