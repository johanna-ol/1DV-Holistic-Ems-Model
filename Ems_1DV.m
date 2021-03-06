function Ems_1DV
% ------------------------------------------------------------------------
% Holistic 1DV model of the Ems
% Solves 1D momentum balance, holistic sediment trasport equation, and
% kw-turbulence Model (Wilcox (1988) and Chmiel et al. (2020))

% Properties:
% Gibson transport equation for consolidation
% Effektive stress: Merckelbach (2000)
% Permeability: Kozeny (1927), Carman (1937) and Malcherek and Cha (2011)
% Rheological model for mud: Bingham
% One sediment fraction, d = 20e-06 m

% This model code has been developed at Universität der Bundeswehr München
% V 1.0 2021-09-07
% ------------------------------------------------------------------------

%% Settings
clc
close all
clear
set(0,'defaultLineLineWidth',2)
set(0,'defaultScatterLineWidth',2)
set(0,'defaultaxesfontsize',14);
set(0,'defaultaxesfontweight','bold');
set(0,'defaultAxesXGrid','on');
set(0,'defaultAxesYGrid','on');
set(0,'defaultAxesGridLineStyle','--');
set(0,'defaultAxesColorOrder',[0 0 1;1 0 0;0 1 0;0 0 0])


%% Variables & constants for the Ems
rhow = 1000;                            % Density water [kg/m^3]
nu0 = 1e-06;                            % Kinematic viscosity [m^2/s]
rhos = 2650;                            % Sediment density [kg/m^3]
d = 20e-06;                             % Particle diameter [m]
theta = 1;                              % Implicity factor [-]
kB = 0;                                 % Bottom boundary condition tke
ks = 3.2e-03;                           % Surface roughness [m]
omegaB = 2500*nu0/ks^2;                 % Bottom boundary condition omega
omegaS = 0.1;                           % Surface boundary condition omega
Sc = 1;                                 % Turbulent Schmidt number [-}
zU = 0;                                 % Bottom [m}
zO = 7.1;                               % Top [m]
KMAX = 30;                              % Maximum number of grid points
dz = ((zO - zU) /KMAX);                 % Mesh spacing [m]
AM2 = 1.46;                             % Amplitude [m]
hm = zO - zU - 1.56;                    % Average Water Depth [m]
g = 9.81;                               % Gravitational acceleration [m/s^2]
c1 = 0.005;                             % Constant for permeability 0.003...0.0055 [-]
c2 = 180;                               % Constant for hindered settling [-]
A = 4e8;                                % Constant for consolidation [Pa]
B = 7.5;                                % Constant for consolidation [-]
le = 6.7e-3;                            % Erosion mixing length [m]

%% Constants k-w-1988
sigmak = 0.5;
alpha = 5/9;
beta = 3/40;
betastar = 0.09;

%% Initial Conditions
v = zeros(KMAX,1);                      % Flow velocity [m/s]
tke = 1e-5*ones(KMAX,1);                % Turbulent kinetik energy [m^2/s^2]
omega = 1e-5*ones(KMAX,1);              % Potential of a dissipation rate [1/s]
c = 28*ones(KMAX,1);                    % Initial sediment concentration [kg/m^3]
Gtkebytke = zeros(KMAX,1);              % G_tke/k
Gtke = zeros(KMAX,1);                   % G_tke
DZalt = dz;                             % Initial value for old mesh spacing [m]
dt = 10;                                % Time step [s]
NT = 30000;                             % Number of timesteps

Zv = zeros(KMAX,NT/10);                 % Matrices for countour plots
Zco = zeros(KMAX,NT/10);
Ztke = zeros(KMAX,NT/10);
Zdvdz = zeros(KMAX,NT/10);

%% Time Loop
for it = 1 : NT
    
    [h, acc, ustar] = tideM2M4(it*dt,hm,AM2,g);                 % Tidal function
    taus = 0*ustar^2;                                           % Wind shear stress
    [DZ,Zc,M] = UpdateVerticalDiscretisation(h,zU,dz,KMAX);     % Mesh update
    
    % Mesh update
    if it ==1
        Malt = M;
        DZalt = DZ(M,1);
        DZalt2 = DZ(M-1,1);
    else
        if M > Malt
            v(M,1) = v(M-1,1);
            tke(M,1) = tke(M-1,1);
            omega(M,1) = omega(M-1,1);
        end
        [c,Malt,DZalt,DZalt2] = change_c(c,DZ,DZalt,DZalt2,M,Malt);
    end
    
    %% Functions  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    dvdz = dfdz(v,Zc,M);                            % Shear rate [1/s]
    dotgamma = max(abs(dvdz),1e-06);                % Shear rate, cropped [1/s]
    rho = (c(1:M)/rhos)*rhos+(1-c(1:M)/rhos)*rhow;  % Density of the suspension [kg/m^3]
    drhodz = dfdz(rho,Zc,M);                        % Density gradient
    nut = tke(1:M)./omega(1:M);                     % Turbulent kinematic viscosity [m^2/s]
    mut = rho.*nut;                                 % Turbulent viscosity [Pa s]
    mu0 = rho.*nu0;                                 % Molecular viscosity [Pa s]
    phis = c(1:M)/rhos;                             % Sediment volume fraction [-]
    tauy = 844000*(phis).^4;                        % Yield Stress [Pa]
    murh = mu0.*exp(20*phis)+tauy./dotgamma;        % Rheological viscosity, Bingham approach [Pa s]
    kf = min(c1*g*d^2/nu0*(1-phis).^3./...
        (phis.^2),1e6);                             % Permeability [m/s]
    wc =(1-phis).*(1-rhos/rhow)*g/nu0*d^2.*min...
        ((c1*(1-phis).^3./max(phis,1e-06)),(1/18./(1+c2*phis)));   % Settling velocity [m/s]
    sigmas = A * phis.^ B;                          % Effective stress [Pa]
    Krh = (1-phis).*kf./(rhow*g).*sigmas;           % Consolidation diffusivity [m^2/s]
    K = Krh+nut+le^2*abs(dotgamma);                 % Holistic diffusivity [m^2/s]
    
    mu = murh+mut;
    muk = murh+sigmak*mut;
    muom = murh+sigmak*mut;
    Pk = tke(1:M)./omega(1:M).*(dotgamma.^2);
    epsbytke = betastar*omega(1:M);
    Pom = alpha*dotgamma.^2;
    epsombyom = beta*omega(1:M);
    
    for in = 1:M
        if drhodz(in)<0
            Gtkebytke(in,1) = g/Sc./rho(in)*drhodz(in)/omega(in);
            Gtke(in,1) = 0;
        else
            Gtkebytke(in,1)= 0;
            Gtke(in,1) = g/Sc/rho(in)*drhodz(in)*tke(in)/omega(in);
        end
    end
    
    Gtkebytke = Gtkebytke(1:M,1);
    Gtke = Gtke(1:M,1);
    
    v = vDGL(v(1:M),M,DZ,mu,rho,acc,dt,theta,taus);
    c = cDGL(c(1:M),M,DZ,dt,K,theta,wc);
    tke = tkeDGL(tke(1:M),M,DZ,muk,rho,Pk+Gtke,epsbytke-Gtkebytke,dt,theta,kB);
    omega = omegaDGL(omega(1:M),M,DZ,muom,rho,Pom,epsombyom,dt,theta,omegaB,omegaS);
    
    % Check mass conservation
    %     cdz = c.*DZ(1:M);
    %     sumc = sum(cdz);
    
    % For Contourplot
    if mod (it,10) == 0 % Reduces matrix size
        for j = 1 : M
            Zv (j,it/10) = abs(v(j,1));
            Zco(j,it/10) = (c(j,1));
            Ztke(j,it/10) = (tke(j,1));
            Zdvdz(j,it/10)= abs(dvdz(j,1));
        end
        for j = M+1 : KMAX+4 % Scale figure for comparison
            Zv (j,it/10) = NaN;
            Zco(j,it/10) = NaN;
            Ztke(j,it/10) = NaN;
            Zdvdz(j,it/10) = NaN;
        end
    end
    
    %% Figures %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    if mod(it,2000)==0
        
        figure(1)
        subplot (341);
        plot(v,Zc/zO,'Linewidth',2)
        xlabel('Velocity [m/s]')
        ylabel('depth [-]')
        ylim([0 1])
        xlim ([-2 2])
        grid on
        drawnow
        
        figure(1)
        subplot(342)
        plot(c,Zc/zO,'Linewidth',2)
        xlabel('Concentration [kg/m^3]')
        ylabel('depth [-]')
        ylim([0 1])
        grid on
        
        figure(1)
        subplot (343)
        plot(tke/ustar^2,Zc/zO,'Linewidth',2)
        xlabel('TKE/u*^2 [-]')
        ylabel('depth [-]')
        xlim([0 4])
        ylim([0 1])
        grid on
        
        figure(1)
        subplot(344)
        plot(omega,Zc/zO,'Linewidth',2)
        xlabel('\omega [1/s]')
        ylabel('depth [-]')
        ylim([0 1])
        grid on
        
        figure(1)
        subplot (345)
        plot(nut/ustar/h,Zc/zO,'Linewidth',2)
        xlabel('turb. viscosity/u*/h [-]')
        ylabel('depth [-]')
        xlim([0 0.1])
        ylim([0 1])
        grid on
        
        figure(1)
        subplot(346)
        semilogx(mu,Zc/zO,'Linewidth',2)
        xlabel('eff. viscosity [kg/m/s]')
        ylabel('depth [-]')
        ylim([0 1])
        grid on
        
        figure(1)
        subplot (347);
        plot(wc,Zc/zO,'Linewidth',2)
        xlabel('Settling Velocity [m/s]')
        ylabel('depth [-]')
        ylim([0 1])
        grid on
        drawnow
        
        figure(1)
        subplot (348);
        plot(c,wc,'Linewidth',2)
        xlabel('Concentration [kg/m^3]')
        ylabel('Settling Velocity [m/s]')
        grid on
        drawnow
        
        figure(1)
        subplot (349);
        plot(K,Zc/zO,'Linewidth',2)
        xlabel('Diffusivity [m^2/s]')
        ylabel('depth [-]')
        ylim([0 1])
        grid on
        drawnow
        
        figure(1)
        subplot (3,4,10);
        plot(drhodz(1:M),Zc/zO,'Linewidth',2)
        xlabel('drhobdz [kg/m^4]')
        ylabel('depth [-]')
        ylim([0 1])
        grid on
        drawnow
        
        figure(1)
        G = Gtkebytke(1:M).*tke(1:M);
        subplot (3,4,11);
        plot(G/ustar^2,Zc/zO,'Linewidth',2)
        xlabel('G/u*^2 [-]')
        ylabel('depth [-]')
        ylim([0 1])
        grid on
        drawnow
   end

    % Vertical plots for 19:00, 22:00 and 02:00
    t1 = 176800/dt;
    t2 = 185800/dt;
    t3 = 200200/dt;
    
    
    if it==t1
        figure(2)
        % 19:30
        subplot (331);
        plot(c(1:M),Zc,'Linewidth',2)
        title('19:30','FontSize',20)
        xlabel('Concentration [g/l]')
        ylabel('depth [m]')
        xlim([0 100])
        ylim([0 8])
        legend('Simulation')
        grid on
        
        subplot (334);
        plot(v(1:M),Zc,'Linewidth',2)
        xlabel('Velocity [m/s]')
        ylabel('depth [m]')
        xlim([-2 2])
        ylim([0 8])
        grid on
        
        subplot (337);
        plot(dvdz(1:M),Zc,'Linewidth',2)
        xlabel('du/dz [1/s]')
        ylabel('depth [m]')
        ylim([0 8])
        xlim([-2 2])
        grid on
        drawnow
    end
    
    if it==t2
        % 22:00
        figure(2)
        subplot (332);
        plot(c(1:M),Zc,'Linewidth',2)
        title('22:00','FontSize',20)
        xlabel('Concentration [g/l]')
        xlim([0 100])
        ylim([0 8])
        grid on
        
        subplot (335);
        plot((v(1:M)),Zc,'Linewidth',2)
        xlabel('Velocity [m/s]')
        xlim([-2 2])
        ylim([0 8])
        grid on
        
        subplot (338);
        plot((dvdz(1:M)),Zc,'Linewidth',2)
        xlabel('du/dz [1/s]')
        ylim([0 8])
        xlim([-2 2])
        grid on
        drawnow
    end
    
    if it == t3
        % 02:00
        figure(2)
        subplot (333);
        plot(c(1:M),Zc,'Linewidth',2)
        title('02:00','FontSize',20)
        xlabel('Concentration [g/l]')
        xlim([0 100])
        ylim([0 8])
        grid on
        
        subplot (336);
        plot((v(1:M)),Zc,'Linewidth',2)
        xlabel('Velocity [m/s]')
        xlim([-2 2])
        ylim([0 8])
        grid on
        
        subplot (339);
        plot((dvdz(1:M)),Zc,'Linewidth',2)
        xlabel('du/dz [1/s]')
        ylim([0 8])
        xlim([-2 2])
        grid on
        drawnow
    end
end

Tanf = 16600/dt;
Tend = 23440/dt;
ZcB = Zco (:,Tanf:Tend);
ZB = (Zv (:,Tanf:Tend));
ZdvdzB = Zdvdz (:,Tanf:Tend);

%% Contourplot
Tges = (datetime(2014,11,19,16,10,00):seconds(10*dt):datetime(2014,11,20,11,10,00))';

figure('Position',[100, 100, 900, 700])

subplot(311)
[xi,yi] = meshgrid(datenum(Tges),linspace(0,8,size(ZB,1)));
contourf(datenum(xi),yi,ZB, 0:0.01:1.5, 'LineStyle', 'none');
datetick('x')
colormap(jet);
co = colorbar;
caxis([0 1.5]);
co.Label.String = 'Velocity [m/s]';
xlabel('date')
ylabel('depth [m]')

subplot(312)
[xi,yi] = meshgrid(datenum(Tges),linspace(0,8,size(ZcB,1)));
contourf(datenum(xi),yi,ZcB, 0:0.2:40, 'LineStyle', 'none');
datetick('x')
colormap(jet);
co = colorbar;
caxis([0 40]);
co.Label.String = 'Concentration [g/l]';
xlabel('date')
ylabel('depth [m]')

subplot(313)
[xi,yi] = meshgrid(datenum(Tges),linspace(0,8,size(ZdvdzB,1)));
contourf(datenum(xi),yi,ZdvdzB, 0:0.01:1.2, 'LineStyle', 'none');
datetick('x')
colormap(jet);
co = colorbar;
caxis([0 1.2]);
co.Label.String = 'Velocity shear [1/s]';
xlabel('date')
ylabel('depth [m]')

end
