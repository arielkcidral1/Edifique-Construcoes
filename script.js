
    // --- CONEXÃO COM BANCO DE DADOS (PREPARAÇÃO) ---
    // Transformamos os dados em funções assíncronas (async).
    // Futuramente, basta trocar o array por algo como: 
    // const res = await fetch('SUA_API/portfolio'); return await res.json();

    async function fetchPortfolioData() {
      try {
        // Chamada para a rota da API que consultará as tabelas 'projects' e 'project_photos'
        const response = await fetch('/api/projetos'); 
        if (!response.ok) return [];
        
        const projetosDB = await response.json();
        
        // Mapeando os dados do banco para o formato visual do site
        return projetosDB.map(projeto => ({
          category: projeto.description || "Projeto", 
          name: projeto.name,
          bgClass: projeto.photo_url ? "" : "p1", // Fallback caso não tenha foto
          bgStyle: projeto.photo_url ? `style="background-image: url('${projeto.photo_url}')"` : ""
        }));
      } catch (error) {
        console.warn("Aguardando backend da API de projetos...");
        return [];
      }
    }

    async function fetchTestimonialsData() {
      try {
        // Chamada para a rota da API que consultará as tabelas 'reviews' e 'customers'
        const response = await fetch('/api/avaliacoes'); 
        if (!response.ok) return [];
        
        const avaliacoesDB = await response.json();

        return avaliacoesDB.map(avaliacao => {
          // Pega as iniciais do nome do cliente para fazer o avatar (Ex: "Marcos Rodrigues" -> "MR")
          const iniciais = avaliacao.customer_name ? avaliacao.customer_name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase() : "CL";

          return {
            stars: avaliacao.rating || 5,
            text: avaliacao.comment,
            avatar: iniciais,
            name: avaliacao.customer_name || "Cliente",
            role: avaliacao.project_name ? `Projeto: ${avaliacao.project_name}` : "Cliente Especial"
          };
        });
      } catch (error) {
        console.warn("Aguardando backend da API de avaliações...");
        return [];
      }
    }

    // --- RENDER FUNCTIONS ---
    function renderPortfolio(data) {
      const grid = document.querySelector('.portfolio-grid');
      if (!grid) return;
      grid.innerHTML = data.map(item => `
        <div class="portfolio-item">
          <div class="portfolio-thumb">
            <div class="portfolio-bg ${item.bgClass}" ${item.bgStyle || ''}></div>
            <div class="portfolio-overlay"></div>
            <div class="portfolio-pattern"></div>
            <div class="portfolio-info">
              <div class="portfolio-cat">${item.category}</div>
              <div class="portfolio-name">${item.name}</div>
            </div>
          </div>
        </div>
      `).join('');
    }

    function renderTestimonials(data) {
      const grid = document.querySelector('.testimonials-grid');
      if (!grid) return;
      grid.innerHTML = data.map(item => `
        <div class="testimonial-card reveal">
          <div class="testimonial-stars">${'★'.repeat(item.stars)}</div>
          <p class="testimonial-text">${item.text}</p>
          <div class="testimonial-author">
            <div class="author-avatar">${item.avatar}</div>
            <div>
              <div class="author-name">${item.name}</div>
              <div class="author-role">${item.role}</div>
            </div>
          </div>
        </div>
      `).join('');
    }

    // Scroll reveal
    function setupRevealAnimation() {
        const reveals = document.querySelectorAll('.reveal');
        const io = new IntersectionObserver(entries => {
          entries.forEach((e, i) => {
            if (e.isIntersecting) {
              const siblings = [...e.target.parentElement.querySelectorAll('.reveal')];
              const idx = siblings.indexOf(e.target);
              e.target.style.transitionDelay = (idx * 0.1) + 's';
              e.target.classList.add('visible');
              io.unobserve(e.target);
            }
          });
        }, { threshold: .12 });
        reveals.forEach(el => io.observe(el));
    }

    // Counter animation
    function animateCount(el, target, suffix) {
      let start = 0;
      const inc = target / 60;
      const t = setInterval(() => {
        start = Math.min(start + inc, target);
        el.textContent = Math.floor(start) + suffix;
        if (start >= target) clearInterval(t);
      }, 25);
    }
    const statsIO = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          const nums = document.querySelectorAll('.stat-num');
          const raw = ['20+','850+','300+','98%'];
          nums.forEach((el, i) => {
            const n = parseInt(raw[i]);
            const s = raw[i].replace(/\d+/, '');
            animateCount(el, n, s);
          });
          statsIO.disconnect();
        }
      });
    }, { threshold: .5 });
    statsIO.observe(document.querySelector('.stats-strip'));


    // Nav background on scroll
    const nav = document.querySelector('nav');
    window.addEventListener('scroll', () => {
      nav.style.background = window.scrollY > 60
        ? 'rgba(20,18,16,.97)'
        : 'linear-gradient(to bottom, rgba(20,18,16,.92) 0%, transparent 100%)';
    });

    // --- INITIALIZATION ---
    // Inicialização assíncrona aguardando resposta do banco de dados
    async function init() {
      try {
        const portfolioData = await fetchPortfolioData();
        const testimonialsData = await fetchTestimonialsData();

        renderPortfolio(portfolioData);
        renderTestimonials(testimonialsData);
        
        setupRevealAnimation();
      } catch (error) {
        console.error("Erro de conexão com o banco de dados:", error);
      }
    }
    
    init();