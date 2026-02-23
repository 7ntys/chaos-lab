import { useEffect, useMemo, useState } from 'react'

function formatPrice(cents) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
  }).format(cents / 100)
}

export default function App() {
  const [menu, setMenu] = useState([])
  const [specials, setSpecials] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false

    async function loadData() {
      try {
        const [menuRes, specialsRes] = await Promise.all([
          fetch('/api/menu'),
          fetch('/api/specials'),
        ])

        if (!menuRes.ok || !specialsRes.ok) {
          throw new Error('Backend unavailable')
        }

        const menuData = await menuRes.json()
        const specialsData = await specialsRes.json()

        if (!cancelled) {
          setMenu(menuData.items || [])
          setSpecials(specialsData.specials || [])
        }
      } catch (err) {
        if (!cancelled) {
          setError(err.message || 'Unexpected error')
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    loadData()

    return () => {
      cancelled = true
    }
  }, [])

  const groupedMenu = useMemo(() => {
    return menu.reduce((acc, item) => {
      if (!acc[item.category]) {
        acc[item.category] = []
      }
      acc[item.category].push(item)
      return acc
    }, {})
  }, [menu])

  return (
    <div className="page">
      <header className="hero">
        <p className="kicker">Chaos Engineering Playground</p>
        <h1>Chaos Cafe</h1>
        <p>
          A production-like cafe app stack with React, Go, Postgres and an Nginx load balancer.
        </p>
      </header>

      {loading && <p className="status">Loading menu...</p>}
      {error && <p className="status error">{error}</p>}

      {!loading && !error && (
        <main>
          <section className="panel">
            <h2>Today&apos;s Specials</h2>
            <div className="special-grid">
              {specials.map((special) => (
                <article key={special.id} className="card">
                  <h3>{special.title}</h3>
                  <p>{special.description}</p>
                </article>
              ))}
            </div>
          </section>

          <section className="panel">
            <h2>Menu</h2>
            {Object.entries(groupedMenu).map(([category, items]) => (
              <div key={category} className="category-block">
                <h3>{category}</h3>
                <div className="menu-list">
                  {items.map((item) => (
                    <article key={item.id} className="menu-item">
                      <div>
                        <h4>{item.name}</h4>
                        <p>{item.description}</p>
                      </div>
                      <strong>{formatPrice(item.price_cents)}</strong>
                    </article>
                  ))}
                </div>
              </div>
            ))}
          </section>
        </main>
      )}
    </div>
  )
}
