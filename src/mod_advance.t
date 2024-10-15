!> Module containing all the time stepping schemes
module mod_advance

  implicit none
  private

  !> Whether to conserve fluxes at the current sub-step
  logical :: fix_conserve_at_step = .true.

  public :: advance
  public :: process
  public :: process_advanced

contains

  !> Advance all the grids over one time step, including all sources
  subroutine advance(iit)
    use mod_global_parameters
    use mod_particles, only: handle_particles
    use mod_source, only: add_split_source

    integer, intent(in) :: iit

    integer :: iigrid, igrid, idimsplit

    ! !$acc update device(ps(1:max_blocks))
    ! do iigrid=1,igridstail; igrid=igrids(iigrid);
    !    !$acc enter data copyin(ps(igrid)%w, ps(igrid)%x) create(ps1(igrid)%w, ps2(igrid)%w)
    ! end do
    
    ! split source addition
    call add_split_source(prior=.true.)

    if (dimsplit) then
       if ((iit/2)*2==iit .or. typedimsplit=='xy') then
          ! do the sweeps in order of increasing idim,
          do idimsplit=1,ndim
             call advect(idimsplit,idimsplit)
          end do
       else
          ! If the parity of "iit" is odd and typedimsplit=xyyx,
          ! do sweeps backwards
          do idimsplit=ndim,1,-1
             call advect(idimsplit,idimsplit)
          end do
       end if
    else
       ! Add fluxes from all directions at once
       call advect(1,ndim)
    end if

    ! split source addition
    call add_split_source(prior=.false.)

    if(use_particles) call handle_particles

    ! do iigrid=1,igridstail; igrid=igrids(iigrid);
    !    !$acc exit data delete(ps(igrid)%x, ps1(igrid)%w, ps2(igrid)%w) copyout(ps(igrid)%w)
    ! end do
    
  end subroutine advance

  !> Advance all grids over one time step, but without taking dimensional
  !> splitting or split source terms into account
  subroutine advect(idim^LIM)
    use mod_global_parameters
    use mod_fix_conserve
    use mod_ghostcells_update
    use mod_physics, only: phys_req_diagonal
    use mod_comm_lib, only: mpistop

    integer, intent(in) :: idim^LIM
    integer             :: iigrid, igrid, ix^D, iw

    call init_comm_fix_conserve(idim^LIM,nwflux)
    fix_conserve_at_step = time_advance .and. levmax>levmin
    
    ! copy w instead of wold because of potential use of dimsplit or sourcesplit
    !$OMP PARALLEL DO PRIVATE(igrid)
    do iigrid=1,igridstail; igrid=igrids(iigrid);
       !$acc parallel loop collapse(ndim+1)
       do iw = 1, nw
          {^D& do ix^DB = ixGlo^DB, ixGhi^DB \}
!          ps1(igrid)%w(ix^D,iw) = ps(igrid)%w(ix^D,iw)
          bg(2)%w(ix^D,iw,igrid) = bg(1)%w(ix^D,iw,igrid)
          {^D& end do \}
       end do
          if(stagger_grid) then
             !$acc kernels
             ps1(igrid)%ws=ps(igrid)%ws
             !$acc end kernels
          end if
    end do
    !$OMP END PARALLEL DO

    istep = 0

     select case (t_stepper)
   !  case (onestep)
   !     select case (t_integrator)
   !     case (Forward_Euler)
   !        call advect1(flux_method,one,idim^LIM,global_time,bg(2),global_time,bg(1))

   !     case (IMEX_Euler)
   !        call advect1(flux_method,one,idim^LIM,global_time,bg(1),global_time,bg(2))
   !        call global_implicit_update(one,dt,global_time+dt,ps,ps1)

   !     case (IMEX_SP)
   !        call global_implicit_update(one,dt,global_time,ps,ps1)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail; igrid=igrids(iigrid);
   !           ps1(igrid)%w=ps(igrid)%w
   !           if(stagger_grid) ps1(igrid)%ws=ps(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,one,idim^LIM,global_time,bg(2),global_time,bg(1))

   !     case default
   !        call mpistop("unkown onestep time_integrator in advect")
   !     end select

   !  case (twostep)
   !     select case (t_integrator)
   !     case (Predictor_Corrector)
   !        ! PC or explicit midpoint
   !        ! predictor step
   !        fix_conserve_at_step = .false.
   !        call advect1(typepred1,half,idim^LIM,global_time,bg(1),global_time,bg(2))
   !        ! corrector step
   !        fix_conserve_at_step = time_advance .and. levmax>levmin
   !        call advect1(flux_method,one,idim^LIM,global_time+half*dt,bg(2),global_time,bg(1))

      !  case (RK2_alf)
      !     ! RK2 with alfa parameter, where rk_a21=alfa
      !     call advect1(flux_method,rk_a21, idim^LIM,global_time,bg(1),global_time,bg(2))
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w = ps(igrid)%w+rk_b1*(ps1(igrid)%w-ps(igrid)%w)/rk_a21
      !        if(stagger_grid) ps(igrid)%ws = ps(igrid)%ws+(one-rk_b2)*(ps1(igrid)%ws-ps(igrid)%ws)/rk_a21
      !     end do
      !     !$OMP END PARALLEL DO
      !     call advect1(flux_method,rk_b2,idim^LIM,global_time+rk_a21*dt,bg(2),global_time+rk_b1*dt,bg(1))

      !  case (ssprk2)
      !     ! ssprk2 or Heun's method
      !     call advect1(flux_method,one, idim^LIM,global_time,bg(1),global_time,bg(2))
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w = half*ps(igrid)%w+half*ps1(igrid)%w
      !        if(stagger_grid) ps(igrid)%ws = half*ps(igrid)%ws+half*ps1(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     call advect1(flux_method,half,idim^LIM,global_time+dt,bg(2),global_time+half*dt,bg(1))

      !  case (IMEX_Midpoint)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps2(igrid)%w = ps(igrid)%w
      !        if(stagger_grid) ps2(igrid)%ws = ps(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     call advect1(flux_method,half, idim^LIM,global_time,bg(1),global_time,bg(2))
      !     call global_implicit_update(half,dt,global_time+half*dt,ps2,ps1)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w = ps(igrid)%w+2.0d0*(ps2(igrid)%w-ps1(igrid)%w)
      !        if(stagger_grid) ps(igrid)%ws = ps(igrid)%ws+2.0d0*(ps2(igrid)%ws-ps1(igrid)%ws)
      !     end do
      !     !$OMP END PARALLEL DO
      !     call advect1(flux_method,one, idim^LIM,global_time+half*dt,bg(3),global_time,bg(1))

      !  case (IMEX_Trapezoidal)
      !     call advect1(flux_method,one, idim^LIM,global_time,bg(1),global_time,bg(2))
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps2(igrid)%w = half*(ps(igrid)%w+ps1(igrid)%w)
      !        if(stagger_grid) ps2(igrid)%ws = half*(ps(igrid)%ws+ps1(igrid)%ws)
      !     end do
      !     !$OMP END PARALLEL DO
      !     call evaluate_implicit(global_time,ps)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps1(igrid)%w = ps1(igrid)%w+half*dt*ps(igrid)%w
      !        if(stagger_grid) ps1(igrid)%ws = ps1(igrid)%ws+half*dt*ps(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w = ps2(igrid)%w+half*dt*ps(igrid)%w
      !        if(stagger_grid) ps(igrid)%ws = ps2(igrid)%ws+half*dt*ps(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     call getbc(global_time+dt,dt,ps1,iwstart,nwgc,phys_req_diagonal)
      !     call global_implicit_update(half,dt,global_time+dt,ps2,ps1)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w = ps(igrid)%w+ps2(igrid)%w-ps1(igrid)%w
      !        if(stagger_grid) ps(igrid)%ws = ps(igrid)%ws+ps2(igrid)%ws-ps1(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     call advect1(flux_method,half, idim^LIM,global_time+dt,bg(3),global_time+half*dt,bg(1))

      !  case (IMEX_222)
      !     ! One-parameter family of schemes (parameter is imex222_lambda) from
      !     ! Pareschi&Russo 2005, which is L-stable (for default lambda) and
      !     ! asymptotically SSP.
      !     ! See doi.org/10.1007/s10915-004-4636-4 (table II)
      !     ! See doi.org/10.1016/j.apnum.2016.10.018 for interesting values of lambda

      !     ! Preallocate ps2 as y^n for the implicit update
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps2(igrid)%w = ps(igrid)%w
      !        if(stagger_grid) ps2(igrid)%ws = ps(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     ! Solve xi1 = y^n + lambda.dt.F_im(xi1)
      !     call global_implicit_update(imex222_lambda, dt, global_time, ps2, ps)

      !     ! Set ps1 = y^n + dt.F_ex(xi1)
      !     call advect1(flux_method, one, idim^LIM, global_time, bg(3), global_time, bg(2))
      !     ! Set ps2 = dt.F_im(xi1)        (is at t^n)
      !     ! Set ps  = y^n + dt/2 . F(xi1) (is at t^n+dt/2)
      !     ! Set ps1 = y^n + dt.F_ex(xi1) + (1-2.lambda).dt.F_im(xi1) and enforce BC (at t^n+dt)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps2(igrid)%w = (ps2(igrid)%w - ps(igrid)%w) / imex222_lambda
      !        if(stagger_grid) ps2(igrid)%ws = (ps2(igrid)%ws - ps(igrid)%ws) / imex222_lambda
      !     end do
      !     !$OMP END PARALLEL DO
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w = half*(ps(igrid)%w + ps1(igrid)%w + ps2(igrid)%w)
      !        if(stagger_grid) ps(igrid)%ws = half*(ps(igrid)%ws + ps1(igrid)%ws + ps2(igrid)%ws)
      !     end do
      !     !$OMP END PARALLEL DO
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps1(igrid)%w = ps1(igrid)%w + (1.0d0 - 2.0d0*imex222_lambda)*ps2(igrid)%w
      !        if(stagger_grid) ps1(igrid)%ws = ps1(igrid)%ws + (1.0d0 - 2.0d0*imex222_lambda)*ps2(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     call getbc(global_time+dt,dt,ps1,iwstart,nwgc,phys_req_diagonal)

      !     ! Preallocate ps2 as xi1 for the implicit update (is at t^n)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps2(igrid)%w = 2.0d0*ps2(igrid)%w - ps1(igrid)%w - imex222_lambda*ps2(igrid)%w
      !        if(stagger_grid) ps2(igrid)%ws = 2.0d0*ps2(igrid)%ws - ps1(igrid)%ws - imex222_lambda*ps2(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     ! Solve xi2 = (ps1) + lambda.dt.F_im(xi2)
      !     call global_implicit_update(imex222_lambda, dt, global_time, ps2, ps1)

      !     ! Add dt/2.F_im(xi2) to ps
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w = ps(igrid)%w + (ps2(igrid)%w - ps1(igrid)%w) / (2.0d0 * imex222_lambda)
      !        if(stagger_grid) ps(igrid)%ws = ps(igrid)%ws + (ps2(igrid)%ws - ps1(igrid)%ws) / (2.0d0 * imex222_lambda)
      !     end do
      !     !$OMP END PARALLEL DO
      !     ! Set ps = y^n + dt/2.(F(xi1)+F(xi2)) = y^(n+1)
      !     call advect1(flux_method, half, idim^LIM, global_time+dt, bg(3), global_time+half*dt, bg(1))

      !  case default
      !     call mpistop("unkown twostep time_integrator in advect")
      !  end select

    case (threestep)
       select case (t_integrator)
       ! AGILE this is our integrator (default threestep)
       case (ssprk3)
          ! this is SSPRK(3,3) Gottlieb-Shu 1998 or SSP(3,2) depending on ssprk_order (3 vs 2)
         
          ! TODO call advect1 with bg(2) instead of ps1 ??? 
          call advect1(flux_method,rk_beta11, idim^LIM,global_time,ps,bg(1),global_time,ps1,bg(2))
          
          !$OMP PARALLEL DO PRIVATE(igrid)
          do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
             !$acc parallel loop collapse(ndim+1)
             do iw = 1, nw
                {^D& do ix^DB = ixGlo^DB, ixGhi^DB \}
!                ps2(igrid)%w(ix^D,iw) = rk_alfa21 * ps(igrid)%w(ix^D,iw) + rk_alfa22 * ps1(igrid)%w(ix^D,iw)
                bg(3)%w(ix^D,iw,igrid) = rk_alfa21 * bg(1)%w(ix^D,iw,igrid) + rk_alfa22 * bg(2)%w(ix^D,iw,igrid)
                {^D& end do \}
             end do
             if(stagger_grid) ps2(igrid)%ws=rk_alfa21*ps(igrid)%ws+rk_alfa22*ps1(igrid)%ws
          end do
          !$OMP END PARALLEL DO
          
          ! TODO call advect1 with bg(3) instead of ps2 ??? 
          call advect1(flux_method,rk_beta22, idim^LIM,global_time+rk_c2*dt,ps1,bg(2),global_time+rk_alfa22*rk_c2*dt,ps2,bg(3))
          
          !$OMP PARALLEL DO PRIVATE(igrid)
          do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
             !$acc parallel loop collapse(ndim+1)
             do iw = 1, nw
                {^D& do ix^DB = ixGlo^DB, ixGhi^DB \}
!                ps(igrid)%w(ix^D,iw) = rk_alfa31 * ps(igrid)%w(ix^D,iw) + rk_alfa33 * ps2(igrid)%w(ix^D,iw)
                bg(1)%w(ix^D,iw,igrid) = rk_alfa31 * bg(1)%w(ix^D,iw,igrid) + rk_alfa33 * bg(3)%w(ix^D,iw,igrid)
                {^D& end do \}
             end do
             if(stagger_grid) ps(igrid)%ws=rk_alfa31*ps(igrid)%ws+rk_alfa33*ps2(igrid)%ws
          end do
          !$OMP END PARALLEL DO
          
          ! TODO call advect1 with bg(1) instead of ps ??? 
          call advect1(flux_method,rk_beta33, &
                idim^LIM,global_time+rk_c3*dt,ps2,bg(3),global_time+(1.0d0-rk_beta33)*dt,ps,bg(1))

      !  case (RK3_BT)
      !     ! this is a general threestep RK according to its Butcher Table
      !     call advect1(flux_method,rk3_a21, idim^LIM,global_time,bg(1),global_time,bg(2))
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps3(igrid)%w=(ps1(igrid)%w-ps(igrid)%w)/rk3_a21
      !        if(stagger_grid) ps3(igrid)%ws=(ps1(igrid)%ws-ps(igrid)%ws)/rk3_a21
      !     end do
      !     !$OMP END PARALLEL DO
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps2(igrid)%w=ps(igrid)%w+rk3_a31*ps3(igrid)%w
      !        if(stagger_grid) ps2(igrid)%ws=ps(igrid)%ws+rk3_a31*ps3(igrid)%ws
      !     end do
      !     !$OMP END PARALLEL DO
      !     call advect1(flux_method,rk3_a32, idim^LIM,global_time+rk3_c2*dt,bg(2),global_time+rk3_a31*dt,bg(3))
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w=ps(igrid)%w+rk3_b1*ps3(igrid)%w &
      !             +rk3_b2*(ps2(igrid)%w-(ps(igrid)%w+rk3_a31*ps3(igrid)%w))/rk3_a32
      !        if(stagger_grid)then
      !            ps(igrid)%ws=ps(igrid)%ws+rk3_b1*ps3(igrid)%ws &
      !              +rk3_b2*(ps2(igrid)%ws-(ps(igrid)%ws+rk3_a31*ps3(igrid)%ws))/rk3_a32
      !        endif
      !     end do
      !     !$OMP END PARALLEL DO
      !     call advect1(flux_method,rk3_b3, idim^LIM,global_time+rk3_c3*dt,bg(3),global_time+(1.0d0-rk3_b3)*dt,bg(1))

      !  case (IMEX_ARS3)
      !     ! this is IMEX scheme ARS3
      !     call advect1(flux_method,ars_gamma, idim^LIM,global_time,bg(1),global_time,bg(2))
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps4(igrid)%w=(ps1(igrid)%w-ps(igrid)%w)/ars_gamma
      !        if(stagger_grid) ps4(igrid)%ws=(ps1(igrid)%ws-ps(igrid)%ws)/ars_gamma
      !     end do
      !     !$OMP END PARALLEL DO
      !     call global_implicit_update(ars_gamma,dt,global_time+ars_gamma*dt,ps2,ps1)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps1(igrid)%w=(ps2(igrid)%w-ps1(igrid)%w)/ars_gamma
      !        if(stagger_grid) ps1(igrid)%ws=(ps2(igrid)%ws-ps1(igrid)%ws)/ars_gamma
      !     end do
      !     !$OMP END PARALLEL DO
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps3(igrid)%w=ps(igrid)%w+(ars_gamma-1.0d0)*ps4(igrid)%w+(1.0d0-2.0d0*ars_gamma)*ps1(igrid)%w
      !        if(stagger_grid) then
      !           ps3(igrid)%ws=ps(igrid)%ws+(ars_gamma-1.0d0)*ps4(igrid)%ws+(1.0d0-2.0d0*ars_gamma)*ps1(igrid)%ws
      !        endif
      !     end do
      !     !$OMP END PARALLEL DO
      !     ! ps3 becomes??
      !     !call advect1(flux_method,2.0d0*(1.0d0-ars_gamma), idim^LIM,global_time+ars_gamma*dt,bg(3),global_time+(ars_gamma-1.0d0)*dt,ps3)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps2(igrid)%w=ps1(igrid)%w+(ps3(igrid)%w-(ps(igrid)%w+ &
      !          (ars_gamma-1.0d0)*ps4(igrid)%w+(1.0d0-2.0d0*ars_gamma)*ps1(igrid)%w))/(2.0d0*(1.0d0-ars_gamma))
      !        if(stagger_grid) then
      !        ps2(igrid)%ws=ps1(igrid)%ws+(ps3(igrid)%ws-(ps(igrid)%ws+ &
      !          (ars_gamma-1.0d0)*ps4(igrid)%ws+(1.0d0-2.0d0*ars_gamma)*ps1(igrid)%ws))/(2.0d0*(1.0d0-ars_gamma))
      !        endif
      !     end do
      !     !$OMP END PARALLEL DO
      !     call global_implicit_update(ars_gamma,dt,global_time+(1.0d0-ars_gamma)*dt,ps4,ps3)
      !     !$OMP PARALLEL DO PRIVATE(igrid)
      !     do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
      !        ps(igrid)%w=ps(igrid)%w+half*ps2(igrid)%w &
      !           +half*(ps4(igrid)%w-ps3(igrid)%w)/ars_gamma
      !        if(stagger_grid) then
      !           ps(igrid)%ws=ps(igrid)%ws+half*ps2(igrid)%ws &
      !               +half*(ps4(igrid)%ws-ps3(igrid)%ws)/ars_gamma
      !        endif
      !     end do
          !$OMP END PARALLEL DO
          ! ps4 becomes?
          !call advect1(flux_method,half, idim^LIM,global_time+(1.0d0-ars_gamma)*dt,ps4,global_time+half*dt,bg(1))

   !     case (IMEX_232)
   !        ! this is IMEX_ARK(2,3,2) or IMEX_SSP(2,3,2)
   !        call advect1(flux_method,imex_a21, idim^LIM,global_time,bg(1),global_time,bg(2))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps4(igrid)%w=(ps1(igrid)%w-ps(igrid)%w)/imex_a21
   !           ps3(igrid)%w=ps(igrid)%w
   !           if(stagger_grid) then
   !             ps4(igrid)%ws=(ps1(igrid)%ws-ps(igrid)%ws)/imex_a21
   !             ps3(igrid)%ws=ps(igrid)%ws
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        call evaluate_implicit(global_time,ps3)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps1(igrid)%w=ps1(igrid)%w+imex_ha21*dt*ps3(igrid)%w
   !           if(stagger_grid) ps1(igrid)%ws=ps1(igrid)%ws+imex_ha21*dt*ps3(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call getbc(global_time+imex_a21*dt,dt,ps1,iwstart,nwgc,phys_req_diagonal)
   !        call global_implicit_update(imex_ha22,dt,global_time+imex_c2*dt,ps2,ps1)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps(igrid)%w=ps(igrid)%w+imex_a31*ps4(igrid)%w &
   !              +imex_b1*dt*ps3(igrid)%w+imex_b2*(ps2(igrid)%w-ps1(igrid)%w)/imex_ha22
   !           if(stagger_grid) then
   !           ps(igrid)%ws=ps(igrid)%ws+imex_a31*ps4(igrid)%ws &
   !              +imex_b1*dt*ps3(igrid)%ws+imex_b2*(ps2(igrid)%ws-ps1(igrid)%ws)/imex_ha22
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps3(igrid)%w=ps1(igrid)%w-imex_a21*ps4(igrid)%w &
   !              -imex_ha21*dt*ps3(igrid)%w+imex_b1*dt*ps3(igrid)%w
   !           if(stagger_grid) then
   !           ps3(igrid)%ws=ps1(igrid)%ws-imex_a21*ps4(igrid)%ws &
   !              -imex_ha21*dt*ps3(igrid)%ws+imex_b1*dt*ps3(igrid)%ws
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,imex_a32, idim^LIM,global_time+imex_c2*dt,bg(3),global_time+imex_a31*dt,bg(1))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps2(igrid)%w=(ps(igrid)%w-ps3(igrid)%w-imex_a31*ps4(igrid)%w)/imex_a32 &
   !              +(1.0d0-imex_b2/imex_a32)*(ps2(igrid)%w-ps1(igrid)%w)/imex_ha22
   !           if(stagger_grid) then
   !           ps2(igrid)%ws=(ps(igrid)%ws-ps3(igrid)%ws-imex_a31*ps4(igrid)%ws)/imex_a32 &
   !              +(1.0d0-imex_b2/imex_a32)*(ps2(igrid)%ws-ps1(igrid)%ws)/imex_ha22
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps1(igrid)%w=ps3(igrid)%w+imex_b1*ps4(igrid)%w+imex_b2*ps2(igrid)%w
   !           if(stagger_grid) then
   !           ps1(igrid)%ws=ps3(igrid)%ws+imex_b1*ps4(igrid)%ws+imex_b2*ps2(igrid)%ws
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        call global_implicit_update(imex_b3,dt,global_time+imex_c3*dt,ps2,ps)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps(igrid)%w=ps1(igrid)%w+ps2(igrid)%w-ps(igrid)%w
   !           if(stagger_grid) then
   !           ps(igrid)%ws=ps1(igrid)%ws+ps2(igrid)%ws-ps(igrid)%ws
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,imex_b3, idim^LIM,global_time+imex_c3*dt,bg(3),global_time+(1.0d0-imex_b3)*dt,bg(1))

   !     case (IMEX_CB3a)
   !        ! Third order IMEX scheme with low-storage implementation (4 registers).
   !        ! From Cavaglieri&Bewley 2015, see doi.org/10.1016/j.jcp.2015.01.031
   !        ! (scheme called "IMEXRKCB3a" there). Uses 3 explicit and 2 implicit stages.
   !        ! Parameters are in imex_bj, imex_cj (same for implicit/explicit),
   !        ! imex_aij (implicit tableau) and imex_haij (explicit tableau).
   !        call advect1(flux_method, imex_ha21, idim^LIM, global_time, bg(1), global_time, bg(2))
   !        call global_implicit_update(imex_a22, dt, global_time+imex_c2*dt, ps2, ps1)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps3(igrid)%w = ps(igrid)%w + imex_a32/imex_a22 * (ps2(igrid)%w - ps1(igrid)%w)
   !           ps(igrid)%w  = ps(igrid)%w + imex_b2 /imex_a22 * (ps2(igrid)%w - ps1(igrid)%w)
   !           ps1(igrid)%w = ps3(igrid)%w
   !           if(stagger_grid) ps3(igrid)%ws = ps(igrid)%ws + imex_a32/imex_a22 * (ps2(igrid)%ws - ps1(igrid)%ws)
   !           if(stagger_grid) ps(igrid)%ws  = ps(igrid)%ws + imex_b2 /imex_a22 * (ps2(igrid)%ws - ps1(igrid)%ws)
   !           if(stagger_grid) ps1(igrid)%ws = ps3(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        !ps3 becomes?
   !        !call advect1(flux_method, imex_ha32, idim^LIM, global_time+imex_c2*dt, bg(3), global_time, ps3)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps(igrid)%w = ps(igrid)%w + imex_b2 /imex_ha32 * (ps3(igrid)%w - ps1(igrid)%w)
   !           if(stagger_grid) ps(igrid)%ws = ps(igrid)%ws + imex_b2 /imex_ha32 * (ps3(igrid)%ws - ps1(igrid)%ws)
   !        end do
   !        call global_implicit_update(imex_a33, dt, global_time+imex_c3*dt, ps1, ps3)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps(igrid)%w = ps(igrid)%w + imex_b3 /imex_a33 * (ps1(igrid)%w - ps3(igrid)%w)
   !           if(stagger_grid) ps(igrid)%ws = ps(igrid)%ws + imex_b3 /imex_a33 * (ps1(igrid)%ws - ps3(igrid)%ws)
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method, imex_b3, idim^LIM, global_time+imex_c3*dt, bg(2), global_time+imex_b2*dt, bg(1))

        case default
           call mpistop("unkown threestep time_integrator in advect")
        end select

   !  case (fourstep)
   !     select case (t_integrator)
   !     case (ssprk4)
   !        ! SSPRK(4,3) or SSP(4,2) depending on ssprk_order (3 vs 2)
   !        ! ssprk43: Strong stability preserving 4 stage RK 3rd order by Ruuth and Spiteri
   !        !    Ruuth & Spiteri J. S C, 17 (2002) p. 211 - 220
   !        !    supposed to be stable up to CFL=2.
   !        ! ssp42: stable up to CFL=3
   !        call advect1(flux_method,rk_beta11, idim^LIM,global_time,bg(1),global_time,bg(2))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps2(igrid)%w=rk_alfa21*ps(igrid)%w+rk_alfa22*ps1(igrid)%w
   !           if(stagger_grid) ps2(igrid)%ws=rk_alfa21*ps(igrid)%ws+rk_alfa22*ps1(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,rk_beta22, idim^LIM,global_time+rk_c2*dt,bg(2),global_time+rk_alfa22*rk_c2*dt,bg(3))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps1(igrid)%w=rk_alfa31*ps(igrid)%w+rk_alfa33*ps2(igrid)%w
   !           if(stagger_grid) ps1(igrid)%ws=rk_alfa31*ps(igrid)%ws+rk_alfa33*ps2(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,rk_beta33, idim^LIM,global_time+rk_c3*dt,bg(3),global_time+rk_alfa33*rk_c3*dt,bg(2))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps(igrid)%w=rk_alfa41*ps(igrid)%w+rk_alfa44*ps1(igrid)%w
   !           if(stagger_grid) ps(igrid)%ws=rk_alfa41*ps(igrid)%ws+rk_alfa44*ps1(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,rk_beta44, idim^LIM,global_time+rk_c4*dt,bg(2),global_time+(1.0d0-rk_beta44)*dt,bg(1))

   !     case (rk4)
   !        ! the standard RK(4,4) method
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps2(igrid)%w=ps(igrid)%w
   !           ps3(igrid)%w=ps(igrid)%w
   !           if(stagger_grid) then
   !              ps2(igrid)%ws=ps(igrid)%ws
   !              ps3(igrid)%ws=ps(igrid)%ws
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,half, idim^LIM,global_time,bg(1),global_time,bg(2))
   !        call advect1(flux_method,half, idim^LIM,global_time+half*dt,bg(2),global_time,bg(3))
   !        ! ps3 becomes?
   !        !call advect1(flux_method,1.0d0, idim^LIM,global_time+half*dt,bg(3),global_time,ps3)
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps(igrid)%w=(1.0d0/3.0d0)*(-ps(igrid)%w+ps1(igrid)%w+2.0d0*ps2(igrid)%w+ps3(igrid)%w)
   !           if(stagger_grid) ps(igrid)%ws=(1.0d0/3.0d0) &
   !               *(-ps(igrid)%ws+ps1(igrid)%ws+2.0d0*ps2(igrid)%ws+ps3(igrid)%ws)
   !        end do
   !        !$OMP END PARALLEL DO
   !        !ps3 becomes?
   !        !call advect1(flux_method,1.0d0/6.0d0, idim^LIM,global_time+dt,ps3,global_time+dt*5.0d0/6.0d0,bg(1))

   !     case default
   !        call mpistop("unkown fourstep time_integrator in advect")
   !     end select

   !  case (fivestep)
   !     select case (t_integrator)
   !     case (ssprk5)
   !        ! SSPRK(5,4) by Ruuth and Spiteri
   !        !bcexch = .false.
   !        call advect1(flux_method,rk_beta11, idim^LIM,global_time,bg(1),global_time,bg(2))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps2(igrid)%w=rk_alfa21*ps(igrid)%w+rk_alfa22*ps1(igrid)%w
   !           if(stagger_grid) ps2(igrid)%ws=rk_alfa21*ps(igrid)%ws+rk_alfa22*ps1(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,rk_beta22, idim^LIM,global_time+rk_c2*dt,bg(2),global_time+rk_alfa22*rk_c2*dt,bg(3))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps1(igrid)%w=rk_alfa31*ps(igrid)%w+rk_alfa33*ps2(igrid)%w
   !           if(stagger_grid) ps1(igrid)%ws=rk_alfa31*ps(igrid)%ws+rk_alfa33*ps2(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,rk_beta33, idim^LIM,global_time+rk_c3*dt,bg(3),global_time+rk_alfa33*rk_c3*dt,bg(2))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps3(igrid)%w=rk_alfa53*ps2(igrid)%w+rk_alfa54*ps1(igrid)%w
   !           if(stagger_grid) ps3(igrid)%ws=rk_alfa53*ps2(igrid)%ws+rk_alfa54*ps1(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps2(igrid)%w=rk_alfa41*ps(igrid)%w+rk_alfa44*ps1(igrid)%w
   !           if(stagger_grid) ps2(igrid)%ws=rk_alfa41*ps(igrid)%ws+rk_alfa44*ps1(igrid)%ws
   !        end do
   !        !$OMP END PARALLEL DO
   !        call advect1(flux_method,rk_beta44, idim^LIM,global_time+rk_c4*dt,bg(2),global_time+rk_alfa44*rk_c4*dt,bg(3))
   !        !$OMP PARALLEL DO PRIVATE(igrid)
   !        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
   !           ps(igrid)%w=ps3(igrid)%w+rk_alfa55*ps2(igrid)%w &
   !              +(rk_beta54/rk_beta44)*(ps2(igrid)%w-(rk_alfa41*ps(igrid)%w+rk_alfa44*ps1(igrid)%w))
   !           if(stagger_grid) then
   !           ps(igrid)%ws=ps3(igrid)%ws+rk_alfa55*ps2(igrid)%ws &
   !              +(rk_beta54/rk_beta44)*(ps2(igrid)%ws-(rk_alfa41*ps(igrid)%ws+rk_alfa44*ps1(igrid)%ws))
   !           endif
   !        end do
   !        !$OMP END PARALLEL DO
   !        !bcexch = .true.
   !        call advect1(flux_method,rk_beta55, idim^LIM,global_time+rk_c5*dt,bg(3),global_time+(1.0d0-rk_beta55)*dt,bg(1))

   !    case default
   !       call mpistop("unkown fivestep time_integrator in advect")
   !    end select

    case default
       call mpistop("unkown time_stepper in advect")
    end select

  end subroutine advect

  !> Implicit global update step within IMEX schemes, advance psa=psb+dtfactor*qdt*F_im(psa)
  subroutine global_implicit_update(dtfactor,qdt,qtC,psa,psb)
    use mod_global_parameters
    use mod_ghostcells_update
    use mod_physics, only: phys_implicit_update, phys_req_diagonal

    type(state), target :: psa(max_blocks)   !< Compute implicit part from this state and update it
    type(state), target :: psb(max_blocks)   !< Will be unchanged, as on entry
    double precision, intent(in) :: qdt      !< overall time step dt
    double precision, intent(in) :: qtC      !< Both states psa and psb at this time level
    double precision, intent(in) :: dtfactor !< Advance psa=psb+dtfactor*qdt*F_im(psa)

    integer                        :: iigrid, igrid

    !> First copy all variables from a to b, this is necessary to account for
    ! quantities is w with no implicit sourceterm
    do iigrid=1,igridstail; igrid=igrids(iigrid);
       psa(igrid)%w = psb(igrid)%w
    end do

    if (associated(phys_implicit_update)) then
       call phys_implicit_update(dtfactor,qdt,qtC,psa,psb)
    end if

    ! enforce boundary conditions for psa
    call getbc(qtC,0.d0,psa,iwstart,nwgc,phys_req_diagonal)

  end subroutine global_implicit_update

  !> Evaluate Implicit part in place, i.e. psa==>F_im(psa)
  subroutine evaluate_implicit(qtC,psa)
    use mod_global_parameters
    use mod_physics, only: phys_evaluate_implicit

    type(state), target :: psa(max_blocks)   !< Compute implicit part from this state and update it
    double precision, intent(in) :: qtC      !< psa at this time level

    if (associated(phys_evaluate_implicit)) then
       call phys_evaluate_implicit(qtC,psa)
    end if

  end subroutine evaluate_implicit

  !> Integrate all grids by one partial step
  subroutine advect1(method,dtfactor,idim^LIM,qtC,psa,bga,qt,psb,bgb)
    use mod_global_parameters
    use mod_ghostcells_update
    use mod_fix_conserve
    use mod_physics
    use mod_finite_volume_all, only: finite_volume_all

    integer, intent(in) :: idim^LIM
    integer :: ixO^L, ixG^L
    type(state), target :: psa(max_blocks) !< Compute fluxes based on this state
    type(state), target :: psb(max_blocks) !< Update solution on this state
    type(block_grid_t), target :: bga(max_blocks) !< Compute fluxes based on this state
    type(block_grid_t), target :: bgb(max_blocks) !< Update solution on this state
    double precision, intent(in) :: dtfactor !< Advance over dtfactor * dt
    double precision, intent(in) :: qtC
    double precision, intent(in) :: qt
    integer, intent(in) :: method(nlevelshi)

    ! cell face flux
    double precision :: fC(ixG^T,1:nwflux,1:ndim)
    ! cell edge flux
    double precision :: fE(ixG^T,sdim:3)
    !$acc declare create(fC,fE)
    double precision :: qdt
    integer :: iigrid, igrid

    istep = istep+1

    ! AGILE doesn't happen in our test case
    ! if(associated(phys_special_advance)) then
    !  call phys_special_advance(qtC,psa)
    ! end if

    qdt=dtfactor*dt
    ! FIXME: AGILE The following replaces the `call advect1_grid` loop. The
    ! `advect1_grid` variable is a function pointer to the configured solver.
    ! Since NVidia doesn't support function pointers, we hard-code to use
    ! `finite_volume_all` here. In the future this needs to be replaced with
    ! some logic to select the desired method.

    ixO^L=ixG^L^LSUBnghostcells;

    call finite_volume_all( &
        method(block%level), &          ! fs_hll
        qdt, dtfactor, &                ! some scalars related to time stepping
        ixG^L,ixO^L, idim^LIM, &      ! bounds for some arrays
        qtC, &                          ! scalar related to time stepping
        psa, &
        bga, &                          ! first block grid
        qt,  &                          ! scalar related to time stepping
        psb, &
        bgb, &                          ! second block grid
        fC, fE &                        ! fluxes
    )
    ! opedit: Just advance the active grids:
    !!$OMP PARALLEL DO PRIVATE(igrid)
    !do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
    !  block=>ps(igrid)
    !  ^D&dxlevel(^D)=rnode(rpdx^D_,igrid);
    !  !$acc update device(dxlevel)
    !  !$acc enter data attach(block)

    !  call advect1_grid(method(block%level),qdt,dtfactor,ixG^LL,idim^LIM,&
    !    qtC,psa(igrid),qt,psb(igrid),fC,fE,rnode(rpdx1_:rnodehi,igrid),ps(igrid)%x)

    !  ! opedit: Obviously, flux is stored only for active grids.
    !  ! but we know in fix_conserve wether there is a passivegneighbor
    !  ! but we know in conserve_fix wether there is a passive neighbor
    !  ! via neighbor_active(i^D,igrid) thus we skip the correction for those.
    !  ! This violates strict conservation when the active/passive interface
    !  ! coincides with a coarse/fine interface.

    !  if (fix_conserve_global .and. fix_conserve_at_step) then
    !    call store_flux(igrid,fC,idim^LIM,nwflux)
    !    if(stagger_grid) call store_edge(igrid,ixG^LL,fE,idim^LIM)
    !  end if

    !  !$acc exit data detach(block)
    !end do
    !!$OMP END PARALLEL DO
    
    ! opedit: Send flux for all grids, expects sends for all
    ! nsend_fc(^D), set in connectivity.t.

    if (fix_conserve_global .and. fix_conserve_at_step) then
      call recvflux(idim^LIM)
      call sendflux(idim^LIM)
      call fix_conserve(psb,idim^LIM,1,nwflux)
      if(stagger_grid) then
        call fix_edges(psb,idim^LIM)
        ! fill the cell-center values from the updated staggered variables
        !$OMP PARALLEL DO PRIVATE(igrid)
        do iigrid=1,igridstail_active; igrid=igrids_active(iigrid);
          call phys_face_to_center(ixM^LL,psb(igrid))
        end do
        !$OMP END PARALLEL DO
      end if
    end if

    ! For all grids: fill ghost cells
!    do iigrid=1,igridstail; igrid=igrids(iigrid);
!       !$acc update self(psb(igrid)%w)
!    end do
    call getbc(qt+qdt,qdt,psb,iwstart,nwgc,phys_req_diagonal)
!    do iigrid=1,igridstail; igrid=igrids(iigrid);
!       !$acc update device(psb(igrid)%w)
!    end do

  end subroutine advect1

  !> Advance a single grid over one partial time step
  subroutine advect1_grid(method,qdt,dtfactor,ixI^L,idim^LIM,qtC,sCT,qt,s,fC,fE,dxs,x)

    !  integrate one grid by one partial step
    use mod_finite_volume_all
    use mod_finite_volume
    use mod_finite_difference
    use mod_tvd
    use mod_source, only: addsource2
    use mod_physics, only: phys_to_primitive
    use mod_global_parameters
    use mod_comm_lib, only: mpistop

    integer, intent(in) :: method
    integer, intent(in) :: ixI^L, idim^LIM
    double precision, intent(in) :: qdt, dtfactor, qtC, qt, dxs(ndim), x(ixI^S,1:ndim)
    type(state), target          :: sCT, s
    double precision :: fC(ixI^S,1:nwflux,1:ndim), wprim(ixI^S,1:nw)
    double precision :: fE(ixI^S,sdim:3)

    integer :: ixO^L

    ixO^L=ixI^L^LSUBnghostcells;
    
    select case (method)
    case (fs_hll,fs_hllc,fs_hllcd,fs_hlld,fs_tvdlf,fs_tvdmu)
       call finite_volume(method,qdt,dtfactor,ixI^L,ixO^L,idim^LIM,qtC,sCT,qt,s,fC,fE,dxs,x)
    case (fs_cd,fs_cd4)
       call centdiff(method,qdt,dtfactor,ixI^L,ixO^L,idim^LIM,qtC,sCT,qt,s,fC,fE,dxs,x)
    !case (fs_hancock)
    !   call hancock(qdt,dtfactor,ixI^L,ixO^L,idim^LIM,qtC,sCT,qt,s,dxs,x)
    case (fs_fd)
       call fd(qdt,dtfactor,ixI^L,ixO^L,idim^LIM,qtC,sCT,qt,s,fC,fE,dxs,x)
    case (fs_tvd)
       call centdiff(fs_cd,qdt,dtfactor,ixI^L,ixO^L,idim^LIM,qtC,sCT,qt,s,fC,fE,dxs,x)
       call tvdlimit(method,qdt,ixI^L,ixO^L,idim^LIM,sCT,qt+qdt,s,fC,dxs,x)
    case (fs_source)
       wprim=sCT%w
       call phys_to_primitive(ixI^L,ixI^L,wprim,x)
       call addsource2(qdt*dble(idimmax-idimmin+1)/dble(ndim),&
            dtfactor*dble(idimmax-idimmin+1)/dble(ndim),&
            ixI^L,ixO^L,1,nw,qtC,sCT%w,wprim,qt,s%w,x,.false.)
    case (fs_nul)
       ! There is nothing to do
    case default
       call mpistop("unknown flux scheme in advect1_grid")
    end select

  end subroutine advect1_grid

  !> process is a user entry in time loop, before output and advance
  !>         allows to modify solution, add extra variables, etc.
  !> Warning: CFL dt already determined (and is not recomputed)!
  subroutine process(iit,qt)
    use mod_usr_methods, only: usr_process_grid, usr_process_global
    use mod_global_parameters
    use mod_ghostcells_update
    use mod_physics, only: phys_req_diagonal
    ! .. scalars ..
    integer,intent(in)          :: iit
    double precision, intent(in):: qt

    integer:: iigrid, igrid

    if (associated(usr_process_global)) then
       call usr_process_global(iit,qt)
    end if

    if (associated(usr_process_grid)) then
      !$OMP PARALLEL DO PRIVATE(igrid)
      do iigrid=1,igridstail; igrid=igrids(iigrid);
         ! next few lines ensure correct usage of routines like divvector etc
         ^D&dxlevel(^D)=rnode(rpdx^D_,igrid);
         block=>ps(igrid)
         call usr_process_grid(igrid,node(plevel_,igrid),ixG^LL,ixM^LL, &
              qt,ps(igrid)%w,ps(igrid)%x)
      end do
      !$OMP END PARALLEL DO
      call getbc(qt,dt,ps,iwstart,nwgc,phys_req_diagonal)
    end if
  end subroutine process

  !> process_advanced is user entry in time loop, just after advance
  !>           allows to modify solution, add extra variables, etc.
  !>           added for handling two-way coupled PIC-MHD
  !> Warning: w is now at global_time^(n+1), global time and iteration at global_time^n, it^n
  subroutine process_advanced(iit,qt)
    use mod_usr_methods, only: usr_process_adv_grid, &
                               usr_process_adv_global
    use mod_global_parameters
    use mod_ghostcells_update
    use mod_physics, only: phys_req_diagonal
    ! .. scalars ..
    integer,intent(in)          :: iit
    double precision, intent(in):: qt

    integer:: iigrid, igrid

    if (associated(usr_process_adv_global)) then
       call usr_process_adv_global(iit,qt)
    end if

    if (associated(usr_process_adv_grid)) then
      !$OMP PARALLEL DO PRIVATE(igrid)
      do iigrid=1,igridstail; igrid=igrids(iigrid);
         ! next few lines ensure correct usage of routines like divvector etc
         ^D&dxlevel(^D)=rnode(rpdx^D_,igrid);
         block=>ps(igrid)

         call usr_process_adv_grid(igrid,node(plevel_,igrid),ixG^LL,ixM^LL, &
              qt,ps(igrid)%w,ps(igrid)%x)
      end do
      !$OMP END PARALLEL DO
      call getbc(qt,dt,ps,iwstart,nwgc,phys_req_diagonal)
    end if
  end subroutine process_advanced

end module mod_advance
